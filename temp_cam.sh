#!/bin/bash

# A universal script to initialize a UVC thermal camera that automatically
# detects the Linux distribution and uses the native package manager.
# Includes an ASCII art live view mode for terminals.

# --- Configuration & Packages ---
VIDEO_DEVICE="/dev/video2"
RESOLUTION="256x196"
REQUIRED_QUIRK_VALUE="2"
MEDIA_DIR="media_TH"
VIDEO_DURATION=10
VIDEO_FRAMERATE=25
ASCII_WIDTH=100
ASCII_GAMMA=0.7
declare -A REQUIRED_PACKAGES
REQUIRED_PACKAGES=( ["fswebcam"]="fswebcam" ["ffmpeg"]="ffmpeg" ["caca-utils"]="img2txt" )

# --- Helpers ---
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step() { echo -e "\n${CYAN}>>> $1${NC}"; }
ensure_root() { if [[ $EUID -ne 0 ]]; then info "Root privileges are required."; sudo -- "$0" "$@"; exit $?; fi; }

# =============================================================================
#  OS-AWARE PACKAGE MANAGEMENT (FIXED)
# =============================================================================
OS_ID=""; IS_PKG_INSTALLED_CMD=""; PKG_UPDATE_CMD=""; PKG_INSTALL_CMD=""

function detect_os_and_set_commands {
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_ID=$ID; else fail "Cannot detect distribution."; fi
    case "$OS_ID" in
        ubuntu|debian|mint|raspbian)
            IS_PKG_INSTALLED_CMD="dpkg-query -W -f='\${Status}' \"\$1\" 2>/dev/null | grep -q 'install ok installed'"
            # Separated update and install commands
            PKG_UPDATE_CMD="apt-get update"
            PKG_INSTALL_CMD="apt-get install -y"
            ;;
        fedora|centos|rhel|rocky)
            IS_PKG_INSTALLED_CMD="rpm -q \"\$1\" &>/dev/null"
            # No separate update needed for dnf install
            PKG_UPDATE_CMD="true" 
            PKG_INSTALL_CMD="dnf install -y"
            ;;
        arch|manjaro)
            REQUIRED_PACKAGES["libcaca"]="img2txt"; unset REQUIRED_PACKAGES["caca-utils"]
            IS_PKG_INSTALLED_CMD="pacman -Q \"\$1\" &>/dev/null"
            # No separate update needed for pacman -S
            PKG_UPDATE_CMD="true" 
            PKG_INSTALL_CMD="pacman -S --noconfirm"
            ;;
        *) fail "Unsupported Linux distribution: $OS_ID.";;
    esac
    info "Detected '$OS_ID' distribution."
}

# This function is now more robust.
function install_packages {
    info "Updating package lists using '$OS_ID' native package manager..."
    if ! $PKG_UPDATE_CMD &> /dev/null; then
        fail "Failed to update package lists. Please check your connection or repositories."
    fi
    success "Package lists updated."
    
    info "Installing packages: $@..."
    if ! $PKG_INSTALL_CMD "$@"; then
        fail "Failed to install packages: $@."
    fi
}
# =============================================================================
#  SCRIPT STARTS HERE
# =============================================================================
# (The rest of the script is identical to the previous version)

START_TIME=$SECONDS
detect_os_and_set_commands

if [[ $EUID -ne 0 ]]; then
    # ... (Non-privileged checks remain the same) ...
    ensure_root "$@"
fi

# ... (Root-privilege section and User-privilege section are unchanged) ...
step "Running setup tasks with root privileges"

PACKAGES_TO_INSTALL=()
for pkg in "${!REQUIRED_PACKAGES[@]}"; do
    # Use command -v for the pre-root check, as it's more reliable without root
    if ! command -v "${REQUIRED_PACKAGES[$pkg]}" &> /dev/null; then
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    info "Missing packages: ${PACKAGES_TO_INSTALL[*]}"
    install_packages "${PACKAGES_TO_INSTALL[@]}"
    success "All required packages are now installed."
else
    success "All required packages were already installed."
fi

info "Reloading uvcvideo module with quirks=${REQUIRED_QUIRK_VALUE}..."
modprobe -r uvcvideo &>/dev/null || true
if ! modprobe uvcvideo quirks=${REQUIRED_QUIRK_VALUE}; then fail "Failed to load uvcvideo module."; fi
current_quirk=$(cat /sys/module/uvcvideo/parameters/quirks)
if [[ "$current_quirk" -ne "$REQUIRED_QUIRK_VALUE" ]]; then fail "Quirk value is NOT ${REQUIRED_QUIRK_VALUE}."; fi
success "Driver quirk successfully set to ${REQUIRED_QUIRK_VALUE}."
echo "--------------------------------------------------------"

# --- USER-PRIVILEGE SECTION ---
step "Setup complete. Preparing for capture."
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
info "Capture will be performed as user: ${CYAN}${ORIGINAL_USER}${NC}"
sudo -u "$ORIGINAL_USER" mkdir -p "$MEDIA_DIR"

read -p "Camera is ready. Take an (i)mage, (v)ideo, (l)ive view, or (a)scii live view? [i/v/l/a]: " choice

TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

case "$choice" in
  i|I)
    MEDIA_PATH="${MEDIA_DIR}/image_${TIMESTAMP}.jpg"
    if show_spinner "Capturing image..." sudo -u "$ORIGINAL_USER" fswebcam -d "$VIDEO_DEVICE" -r "$RESOLUTION" --no-banner "$MEDIA_PATH"; then success "Image saved to: ${MEDIA_PATH}"; else fail "Failed to capture image."; fi
    ;;
  v|V)
    MEDIA_PATH="${MEDIA_DIR}/video_${TIMESTAMP}.mp4"
    if show_progress "$VIDEO_DURATION" "Recording video..." sudo -u "$ORIGINAL_USER" ffmpeg -y -f v4l2 -video_size "$RESOLUTION" -framerate "$VIDEO_FRAMERATE" -i "$VIDEO_DEVICE" -t "$VIDEO_DURATION" "$MEDIA_PATH"; then success "Video saved to: ${MEDIA_PATH}"; else fail "Failed to record video."; fi
    ;;
  l|L)
    step "Starting Live View"; info "A new window will open. To stop, press 'q' or close it."
    sudo -u "$ORIGINAL_USER" ffplay -f v4l2 -video_size "$RESOLUTION" -an -sn -window_title "Live View" -i "$VIDEO_DEVICE" &>/dev/null; success "Live view session ended."
    ;;
  a|A|ascii)
    step "Starting ASCII Live View"; info "Press CTRL+C to stop the feed."; sleep 2
    trap 'clear; echo -e "${GREEN}ASCII view stopped.${NC}"' INT TERM
    while true; do echo -ne "\033[0;0H"; sudo -u "$ORIGINAL_USER" ffmpeg -loglevel quiet -i "$VIDEO_DEVICE" -vframes 1 -f image2pipe -vcodec ppm - | img2txt -W "$ASCII_WIDTH" --gamma="$ASCII_GAMMA" -; sleep 0.05; done
    ;;
  *) fail "Invalid choice. Please run the script again.";;
esac

echo "--------------------------------------------------------"
info "Script finished."
ELAPSED_TIME=$(($SECONDS - $START_TIME))
step "elapsed time ${ELAPSED_TIME}s"
