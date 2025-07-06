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

# --- Helpers (no changes) ---
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step() { echo -e "\n${CYAN}>>> $1${NC}"; }

# --- NEW: Usage function ---
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

# Check if required arguments are provided
if [ -z "$ACTION" ] || [ -z "$VIDEO_DEVICE" ]; then
    usage
fi

# =============================================================================
#  Root privilege and driver setup (no changes)
# =============================================================================

function ensure_root {
    if [[ $EUID -ne 0 ]]; then
        info "Root privileges are required. Re-running with sudo..."
        sudo -- "$0" "$@"
        exit $?
    fi
}

ensure_root "$@"

step "Running setup tasks with root privileges"
info "Reloading uvcvideo module with quirks=${REQUIRED_QUIRK_VALUE}..."
modprobe -r uvcvideo &>/dev/null || true
if ! modprobe uvcvideo quirks=${REQUIRED_QUIRK_VALUE}; then fail "Failed to load uvcvideo module."; fi
success "Driver setup complete."
echo "--------------------------------------------------------"

# =============================================================================
#  Action Section (replaces the user menu)
# =============================================================================
step "Performing action: '$ACTION' on device '$VIDEO_DEVICE'"
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
sudo -u "$ORIGINAL_USER" mkdir -p "$MEDIA_DIR"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

case "$ACTION" in
  image)
    MEDIA_PATH="${MEDIA_DIR}/image_${TIMESTAMP}.jpg"
    info "Capturing image... (This is usually instantaneous)"
    if sudo -u "$ORIGINAL_USER" fswebcam -d "$VIDEO_DEVICE" -r "$RESOLUTION" --no-banner "$MEDIA_PATH"; then
        success "Image saved to: ${MEDIA_PATH}"
    else
        fail "Failed to capture image."
    fi
    ;;
  video)
    MEDIA_PATH="${MEDIA_DIR}/video_${TIMESTAMP}.mp4"
    info "Recording ${VIDEO_DURATION}s video..."
    # Launch ffmpeg in the background
    sudo -u "$ORIGINAL_USER" ffmpeg -y -f v4l2 -video_size "$RESOLUTION" -framerate "$VIDEO_FRAMERATE" -i "$VIDEO_DEVICE" -t "$VIDEO_DURATION" "$MEDIA_PATH" &>/dev/null &
    FFMPEG_PID=$!

    # --- NEW Progress Bar Logic ---
    tput civis # Hide cursor
    start_time=$(date +%s)
    MAX_BAR_WIDTH=60 # The maximum number of '#' characters to display at 100%

    while kill -0 "$FFMPEG_PID" &>/dev/null; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        # Clamp elapsed time to the max duration to avoid progress > 100%
        if (( elapsed > VIDEO_DURATION )); then elapsed=$VIDEO_DURATION; fi
        
        percent=$(( (elapsed * 100) / VIDEO_DURATION ))
        filled_len=$(( (MAX_BAR_WIDTH * percent) / 100 ))
        
        # Build the bar string with '#' characters
        bar=""
        for ((i=0; i<$filled_len; i++)); do bar+="#"; done
        
        # Print the bar using \r to return to the line start, and 'tput el' to clear the rest of the line
        printf "\r%s$(tput el)" "$bar"
        
        # Break the loop if we are done, to avoid an extra sleep.
        if (( elapsed >= VIDEO_DURATION )); then break; fi

        sleep 0.2
    done
    
    tput cnorm # Restore cursor
    printf "\n" # Move to a new line after the progress bar is complete

    # Wait for ffmpeg to finish and check its exit code
    wait "$FFMPEG_PID"
    if [ $? -eq 0 ]; then
        success "Video saved to: ${MEDIA_PATH}"
    else
        fail "Failed to record video."
    fi
    ;;
  live)
    info "Starting live view... Close the window to exit. (Requires a graphical session)"
    # Run ffplay in the foreground. Script will wait here until the user closes the window.
    sudo -u "$ORIGINAL_USER" DISPLAY=:0 ffplay -f v4l2 -video_size "$RESOLUTION" -an -sn -window_title "Live View (Close window to exit)" -i "$VIDEO_DEVICE" &>/dev/null
    success "Live view session ended."
    ;;
  *)
    fail "Invalid action: '$ACTION'. Please use 'image', 'video', or 'live'."
    ;;
esac

echo "--------------------------------------------------------"
info "Script finished."
