#!/bin/bash

# A non-interactive, argument-driven script to control a UVC camera.
# Designed to be run headlessly or from other automated scripts.

# --- Default Configuration (can be overridden by args) ---
RESOLUTION="256x196"
REQUIRED_QUIRK_VALUE="2"
MEDIA_DIR="media_TH"
VIDEO_DURATION=10
VIDEO_FRAMERATE=25
# ---------------------

# --- Helpers ---
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step() { echo -e "\n${CYAN}>>> $1${NC}"; }

# --- NEW: Dependency Checker ---
function check_deps {
    step "Checking for required tools..."
    local missing_pkg=0
    for cmd in ffmpeg ffplay fswebcam; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "  ${RED}Command not found: $cmd${NC}"
            missing_pkg=1
        else
            echo -e "  ${GREEN}Found: $cmd${NC}"
        fi
    done
    if [ "$missing_pkg" -eq 1 ]; then
        fail "Please install the missing packages to continue."
    fi
}

function usage {
    echo "Usage: $0 <action> <video_device>"
    echo "Actions:"
    echo "  image       Take a single picture."
    echo "  video       Record a ${VIDEO_DURATION}-second video with a progress bar."
    echo "  live        Start a live view (requires a display)."
    echo "Example: $0 video /dev/video0"
    exit 1
}

# --- Argument Parsing ---
ACTION="$1"
VIDEO_DEVICE="$2"

if [ -z "$ACTION" ] || [ -z "$VIDEO_DEVICE" ]; then
    usage
fi

# =============================================================================
#  Root privilege and driver setup
# =============================================================================

function ensure_root {
    if [[ $EUID -ne 0 ]]; then
        info "Root privileges are required for driver setup. Re-running with sudo..."
        # Preserve the critical DISPLAY and XAUTHORITY variables when elevating to sudo
        sudo -E -- "$0" "$@"
        exit $?
    fi
}

# Run dependency checks first, as the user (not root)
if [[ $EUID -ne 0 ]]; then
    check_deps
fi

ensure_root "$@"

step "Running setup tasks with root privileges"
info "Reloading uvcvideo module with quirks=${REQUIRED_QUIRK_VALUE}..."
modprobe -r uvcvideo &>/dev/null || true
if ! modprobe uvcvideo quirks=${REQUIRED_QUIRK_VALUE}; then fail "Failed to load uvcvideo module."; fi
success "Driver setup complete."
echo "--------------------------------------------------------"

# =============================================================================
#  Action Section
# =============================================================================
step "Performing action: '$ACTION' on device '$VIDEO_DEVICE'"
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
# Create media directory as the original user to avoid permission issues
sudo -u "$ORIGINAL_USER" mkdir -p "$MEDIA_DIR"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

case "$ACTION" in
  image)
    MEDIA_PATH="${MEDIA_DIR}/image_${TIMESTAMP}.jpg"
    info "Capturing image..."
    if sudo -u "$ORIGINAL_USER" fswebcam -d "$VIDEO_DEVICE" -r "$RESOLUTION" --no-banner "$MEDIA_PATH"; then
        success "Image saved to: ${MEDIA_PATH}"
    else
        fail "Failed to capture image."
    fi
    ;;
  video)
    MEDIA_PATH="${MEDIA_DIR}/video_${TIMESTAMP}.mp4"
    info "Recording ${VIDEO_DURATION}s video..."
    sudo -u "$ORIGINAL_USER" ffmpeg -y -f v4l2 -video_size "$RESOLUTION" -framerate "$VIDEO_FRAMERATE" -i "$VIDEO_DEVICE" -t "$VIDEO_DURATION" "$MEDIA_PATH" &>/dev/null &
    FFMPEG_PID=$!

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
        for ((i=0; i<$filled_len; i++)); do bar+="#"; done
        printf "\r%s$(tput el)" "$bar"
        if (( elapsed >= VIDEO_DURATION )); then break; fi
        sleep 0.2
    done
    tput cnorm
    printf "\n"
    
    wait "$FFMPEG_PID"
    if [ $? -eq 0 ]; then
        success "Video saved to: ${MEDIA_PATH}"
    else
        fail "Failed to record video."
    fi
    ;;
  live)
    info "Starting live view... Close the window to exit. (Requires a graphical session)"
    
    # CRITICAL: Check for DISPLAY variable as the original user.
    if ! sudo -u "$ORIGINAL_USER" printenv DISPLAY &>/dev/null; then
        fail "No graphical session detected (DISPLAY variable is not set). Cannot start live view."
    fi
    
    # Run ffplay as the original user, passing the necessary environment variables.
    # We REMOVED &>/dev/null so that errors will be printed if it fails.
    sudo -u "$ORIGINAL_USER" \
        DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
        ffplay -f v4l2 -video_size "$RESOLUTION" -an -sn -window_title "Live View (Close window to exit)" -i "$VIDEO_DEVICE"

    if [ $? -ne 0 ]; then
        fail "ffplay exited with an error. Ensure you are running this script from a graphical desktop."
    else
        success "Live view session ended."
    fi
    ;;
  *)
    fail "Invalid action: '$ACTION'. Please use 'image', 'video', or 'live'."
    ;;
esac

echo "--------------------------------------------------------"
info "Script finished."
