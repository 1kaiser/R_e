#!/bin/bash

# A non-interactive, argument-driven script to control a HIK UVC thermal camera.
# Designed to be run headlessly or from other automated scripts.
# Fixes applied:
#   - Auto-detects the correct /dev/videoX node for the HIK camera (2bdf:0102)
#   - Replaces fswebcam with ffmpeg (which is installed)
#   - Persists uvcvideo quirks=2 via /etc/modprobe.d so reconnects work automatically
#   - Skips warmup frames to avoid corrupted first-frame captures
#   - Handles device disconnection gracefully with retries
#   - Uses feh for inline image viewing if a DISPLAY is available

# --- Default Configuration ---
RESOLUTION="256x196"           # Full frame incl. 4 metadata rows; thermal data is rows 0-191
THERMAL_RESOLUTION="256x192"   # Native thermal sensor resolution (after cropping metadata)
REQUIRED_QUIRK_VALUE="2"
MEDIA_DIR="media_TH"
VIDEO_DURATION=10
VIDEO_FRAMERATE=25
WARMUP_FRAMES=3                # Frames to skip before real capture (avoids corrupted first frame)
DEVICE_RETRY_SECS=10           # Seconds to wait for device when not found
# ----------------------------

# --- Colour Helpers ---
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
fail()    { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info()    { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()    { echo -e "\n${CYAN}>>> $1${NC}"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# --- Dependency Checker ---
function check_deps {
    step "Checking for required tools..."
    local missing=0
    for cmd in ffmpeg v4l2-ctl; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "  ${RED}Command not found: $cmd${NC}"
            missing=1
        else
            echo -e "  ${GREEN}Found: $cmd${NC}"
        fi
    done
    # feh is optional - only needed for 'image' action with a display
    if command -v feh &>/dev/null; then
        echo -e "  ${GREEN}Found: feh (image viewer)${NC}"
    else
        echo -e "  ${YELLOW}Optional: feh not found - captured images won't auto-preview${NC}"
    fi
    if [ "$missing" -eq 1 ]; then
        fail "Please install the missing packages: sudo apt-get install ffmpeg v4l2-utils"
    fi
}

function usage {
    echo "Usage: $0 <action> [video_device]"
    echo ""
    echo "Actions:"
    echo "  image   Take a single picture (saved as JPEG)."
    echo "  video   Record a ${VIDEO_DURATION}-second video."
    echo "  live    Start a live view (requires a graphical session)."
    echo ""
    echo "video_device is optional. If omitted, the HIK camera (2bdf:0102) is auto-detected."
    echo ""
    echo "Examples:"
    echo "  $0 image"
    echo "  $0 image /dev/video0"
    echo "  $0 video /dev/video0"
    exit 1
}

# --- Auto-detect HIK camera node ---
# Looks for a UVC camera matching the HIK USB ID (2bdf:0102).
# Returns the first /dev/videoX node associated with it.
function find_hik_device {
    # Check if the USB device is even connected
    if ! lsusb | grep -q "2bdf:0102"; then
        return 1
    fi
    # Find the video node via v4l2-ctl
    local device
    device=$(v4l2-ctl --list-devices 2>/dev/null | grep -A2 "UVC Camera" | grep -oP '/dev/video\d+' | head -1)
    if [ -n "$device" ] && [ -c "$device" ]; then
        echo "$device"
        return 0
    fi
    return 1
}

# --- Wait for device with timeout ---
function wait_for_device {
    local requested_dev="$1"
    info "Waiting up to ${DEVICE_RETRY_SECS}s for device to become available..."
    local waited=0
    while [ $waited -lt $DEVICE_RETRY_SECS ]; do
        if [ -n "$requested_dev" ]; then
            # Specific device requested - check if it exists
            if [ -c "$requested_dev" ]; then
                echo "$requested_dev"
                return 0
            fi
        else
            # Auto-detect mode
            local found
            found=$(find_hik_device)
            if [ -n "$found" ]; then
                echo "$found"
                return 0
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# --- Argument Parsing ---
ACTION="$1"
VIDEO_DEVICE_ARG="$2"   # optional

if [ -z "$ACTION" ]; then
    usage
fi

# --- Root privilege setup ---
function ensure_root {
    if [[ $EUID -ne 0 ]]; then
        info "Root privileges required for driver setup. Re-running with sudo..."
        sudo -E -- "$0" "$@"
        exit $?
    fi
}

# Run dependency check as regular user first
if [[ $EUID -ne 0 ]]; then
    check_deps
fi

ensure_root "$@"

# =============================================================================
#  Driver Setup - Persist quirks so reconnects work automatically
# =============================================================================
step "Setting up uvcvideo driver with quirks=${REQUIRED_QUIRK_VALUE}"

MODPROBE_CONF="/etc/modprobe.d/uvcvideo-hik.conf"
EXPECTED_CONF="options uvcvideo quirks=${REQUIRED_QUIRK_VALUE}"

if [ "$(cat "$MODPROBE_CONF" 2>/dev/null)" != "$EXPECTED_CONF" ]; then
    info "Writing persistent quirks config to ${MODPROBE_CONF}..."
    echo "$EXPECTED_CONF" > "$MODPROBE_CONF"
    success "Quirks config written - will survive reboots & reconnects."
else
    info "Persistent quirks config already in place."
fi

# Reload module only if quirks are NOT already active
ACTIVE_QUIRKS=$(cat /sys/bus/usb/drivers/uvcvideo/*/quirks 2>/dev/null | head -1)
if [ "$ACTIVE_QUIRKS" != "0x$REQUIRED_QUIRK_VALUE" ] && [ "$ACTIVE_QUIRKS" != "$REQUIRED_QUIRK_VALUE" ]; then
    info "Reloading uvcvideo module with quirks=${REQUIRED_QUIRK_VALUE}..."
    # Stop wireplumber temporarily to release device lock
    systemctl --user stop wireplumber 2>/dev/null || true
    sleep 0.5
    modprobe -r uvcvideo &>/dev/null || warn "Could not unload uvcvideo (may be in use - continuing anyway)"
    modprobe uvcvideo "quirks=${REQUIRED_QUIRK_VALUE}" || fail "Failed to load uvcvideo module."
    systemctl --user start wireplumber 2>/dev/null || true
    sleep 1
    success "Driver reloaded with quirks=${REQUIRED_QUIRK_VALUE}."
else
    success "Driver already running with correct quirks."
fi

echo "--------------------------------------------------------"

# =============================================================================
#  Resolve the video device
# =============================================================================
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
step "Resolving video device..."

VIDEO_DEVICE=$(wait_for_device "$VIDEO_DEVICE_ARG")
if [ -z "$VIDEO_DEVICE" ]; then
    fail "HIK camera not found. Is it plugged in? (checked for USB ID 2bdf:0102)"
fi
success "Using device: ${VIDEO_DEVICE}"

# Verify formats are readable
if ! v4l2-ctl --device="$VIDEO_DEVICE" --list-formats-ext &>/dev/null; then
    fail "Cannot query formats on ${VIDEO_DEVICE}. Device may be in use or unavailable."
fi

# =============================================================================
#  Action Section
# =============================================================================
step "Performing action: '$ACTION' on device '$VIDEO_DEVICE'"
sudo -u "$ORIGINAL_USER" mkdir -p "$MEDIA_DIR"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

case "$ACTION" in
  image)
    MEDIA_PATH="${MEDIA_DIR}/image_${TIMESTAMP}.jpg"
    info "Warming up camera (skipping ${WARMUP_FRAMES} frames)..."

    # Use ffmpeg: skip warmup frames, capture 1 frame, encode as JPEG
    # -update 1 is required for single-image output in ffmpeg >= 6.x
    if sudo -u "$ORIGINAL_USER" ffmpeg -loglevel warning \
        -f v4l2 -video_size "$RESOLUTION" -framerate "$VIDEO_FRAMERATE" \
        -i "$VIDEO_DEVICE" \
        -vf "select=gte(n\,${WARMUP_FRAMES})" \
        -vframes 1 \
        -update 1 \
        "$MEDIA_PATH"; then
        success "Image saved to: ${MEDIA_PATH}"
        # Preview with feh if a display is available
        if command -v feh &>/dev/null && sudo -u "$ORIGINAL_USER" printenv DISPLAY &>/dev/null; then
            info "Opening preview with feh..."
            sudo -u "$ORIGINAL_USER" \
                DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
                feh --scale-down --auto-zoom --borderless \
                    --image-bg black --draw-filename --draw-tinted \
                    "$MEDIA_PATH" &
        else
            info "No graphical session detected - skipping feh preview."
            info "To view: feh ${MEDIA_PATH}"
        fi
    else
        fail "Failed to capture image from ${VIDEO_DEVICE}."
    fi
    ;;

  video)
    MEDIA_PATH="${MEDIA_DIR}/video_${TIMESTAMP}.mp4"
    info "Recording ${VIDEO_DURATION}s video at ${VIDEO_FRAMERATE}fps..."

    sudo -u "$ORIGINAL_USER" ffmpeg -loglevel warning \
        -f v4l2 -video_size "$RESOLUTION" -framerate "$VIDEO_FRAMERATE" \
        -i "$VIDEO_DEVICE" \
        -t "$VIDEO_DURATION" \
        -c:v libx264 -preset fast -crf 23 \
        "$MEDIA_PATH" &
    FFMPEG_PID=$!

    # Progress bar
    tput civis
    start_time=$(date +%s)
    MAX_BAR_WIDTH=60
    while kill -0 "$FFMPEG_PID" &>/dev/null; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        if (( elapsed > VIDEO_DURATION )); then elapsed=$VIDEO_DURATION; fi
        percent=$(( (elapsed * 100) / VIDEO_DURATION ))
        filled_len=$(( (MAX_BAR_WIDTH * percent) / 100 ))
        bar=""
        for ((i=0; i<filled_len; i++)); do bar+="#"; done
        printf "\r  [%-${MAX_BAR_WIDTH}s] %d%%" "$bar" "$percent"
        if (( elapsed >= VIDEO_DURATION )); then break; fi
        sleep 0.5
    done
    tput cnorm
    printf "\n"

    wait "$FFMPEG_PID"
    if [ $? -eq 0 ]; then
        success "Video saved to: ${MEDIA_PATH}"
    else
        fail "Failed to record video from ${VIDEO_DEVICE}."
    fi
    ;;

  live)
    info "Starting live view... Close the window to exit. (Requires a graphical session)"

    if ! sudo -u "$ORIGINAL_USER" printenv DISPLAY &>/dev/null; then
        fail "No DISPLAY variable set. Cannot start live view without a graphical session."
    fi

    info "Streaming ${THERMAL_RESOLUTION} @ ${VIDEO_FRAMERATE}fps via ffplay..."
    sudo -u "$ORIGINAL_USER" \
        DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
        ffplay -loglevel warning \
            -f v4l2 -video_size "$RESOLUTION" \
            -framerate "$VIDEO_FRAMERATE" \
            -an -sn \
            -vf "crop=${THERMAL_RESOLUTION}:0:0" \
            -window_title "HIK Thermal Camera - Live View (close to exit)" \
            -i "$VIDEO_DEVICE"

    if [ $? -ne 0 ]; then
        fail "ffplay exited with an error."
    else
        success "Live view session ended."
    fi
    ;;

  *)
    fail "Unknown action: '$ACTION'. Valid actions are: image, video, live"
    ;;
esac

echo "--------------------------------------------------------"
info "Script finished."
