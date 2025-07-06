#!/bin/bash

# A universal script to initialize a UVC thermal camera that automatically
# detects the Linux distribution and uses the native package manager.

# --- Configuration ---
VIDEO_DEVICE="/dev/video2"
RESOLUTION="256x196"
REQUIRED_QUIRK_VALUE="2"
MEDIA_DIR="media_TH"
VIDEO_DURATION=10
VIDEO_FRAMERATE=25
# List of packages that provide the required commands.
# ffplay is provided by the ffmpeg package on all major distros.
REQUIRED_PACKAGES=("fswebcam" "ffmpeg")
# ---------------------

# --- Color Codes & Helpers ---
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step() { echo -e "\n${CYAN}>>> $1${NC}"; }

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        info "Root privileges are required. Attempting to re-run with sudo..."
        sudo -- "$0" "$@"
        exit $?
    fi
}

# =============================================================================
#  OS-AWARE PACKAGE MANAGEMENT FUNCTIONS
# =============================================================================

# Global variables for the package manager
OS_ID=""
IS_PKG_INSTALLED_CMD=""
PKG_INSTALL_CMD=""

# Detects the OS and sets the appropriate package management commands.
function detect_os_and_set_commands {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        fail "Cannot detect Linux distribution (missing /etc/os-release)."
    fi

    case "$OS_ID" in
        ubuntu|debian|mint|raspbian)
            # dpkg-query is more reliable than dpkg -s
            IS_PKG_INSTALLED_CMD="dpkg-query -W -f='\${Status}' \"\$1\" 2>/dev/null | grep -q 'install ok installed'"
            PKG_INSTALL_CMD="apt-get update > /dev/null && apt-get install -y"
            ;;
        fedora|centos|rhel|rocky)
            IS_PKG_INSTALLED_CMD="rpm -q \"\$1\" &>/dev/null"
            PKG_INSTALL_CMD="dnf install -y"
            ;;
        arch|manjaro)
            IS_PKG_INSTALLED_CMD="pacman -Q \"\$1\" &>/dev/null"
            PKG_INSTALL_CMD="pacman -S --noconfirm"
            ;;
        *)
            fail "Unsupported Linux distribution: $OS_ID. Please install packages manually."
            ;;
    esac
    info "Detected '$OS_ID' distribution."
}

# Checks if a given package is installed using the native method.
function is_package_installed {
    eval "$IS_PKG_INSTALLED_CMD"
}

# Installs packages using the native package manager.
function install_packages {
    info "Installing with '$OS_ID' native package manager..."
    if ! $PKG_INSTALL_CMD "$@"; then
        fail "Failed to install packages: $@."
    fi
}


# =============================================================================
#  SCRIPT STARTS HERE
# =============================================================================
START_TIME=$SECONDS

# Always detect the OS first, even as a normal user.
detect_os_and_set_commands

if [[ $EUID -ne 0 ]]; then
    step "Performing non-privileged pre-flight checks..."
    KERNEL_VERSION=$(uname -r)
    UVC_MODULE_PATH="/lib/modules/${KERNEL_VERSION}/kernel/drivers/media/usb/uvc/uvcvideo.ko"
    info "Checking for core video driver file..."
    if [ ! -f "$UVC_MODULE_PATH" ]; then
        fail "UVC driver (uvcvideo.ko) not found for kernel ($KERNEL_VERSION).\n       On Debian/Ubuntu, try: sudo apt install linux-modules-extra-${KERNEL_VERSION}"
    fi
    success "Core UVC video driver file found."
    
    NEEDS_SUDO=false
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! is_package_installed "$pkg"; then
            info "Package '$pkg' is not installed. Installation will require sudo."
            NEEDS_SUDO=true
        fi
    done
    if [ "$NEEDS_SUDO" = false ]; then success "All required packages are already installed."; fi
    
    echo "--------------------------------------------------------"
    info "Listing connected USB devices (lsusb):"
    lsusb
    echo "--------------------------------------------------------"
    ensure_root "$@"
fi

# =============================================================================
#  ROOT-PRIVILEGE SECTION
# =============================================================================
step "Running setup tasks with root privileges"

PACKAGES_TO_INSTALL=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_package_installed "$pkg"; then
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

info "Verifying driver parameter..."
current_quirk=$(cat /sys/module/uvcvideo/parameters/quirks)
info "Current 'quirks' value is: $current_quirk"
if [[ "$current_quirk" -ne "$REQUIRED_QUIRK_VALUE" ]]; then fail "Quirk value is NOT ${REQUIRED_QUIRK_VALUE}."; fi
success "Driver quirk successfully set to ${REQUIRED_QUIRK_VALUE}."
echo "--------------------------------------------------------"

# =============================================================================
#  USER-PRIVILEGE SECTION
# =============================================================================
step "Setup complete. Preparing for capture."
ORIGINAL_USER=${SUDO_USER:-$(whoami)}
info "Capture will be performed as user: ${CYAN}${ORIGINAL_USER}${NC}"
sudo -u "$ORIGINAL_USER" mkdir -p "$MEDIA_DIR"

read -p "Camera is ready. Take an (i)mage, record a (v)ideo, or start a (l)ive view? [i/v/l]: " choice

TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

case "$choice" in
  i|I)
    MEDIA_PATH="${MEDIA_DIR}/image_${TIMESTAMP}.jpg"
    if show_spinner "Capturing image..." sudo -u "$ORIGINAL_USER" fswebcam -d "$VIDEO_DEVICE" -r "$RESOLUTION" --no-banner "$MEDIA_PATH"; then
        success "Image saved to: ${MEDIA_PATH}"
    else fail "Failed to capture image."; fi
    ;;
  v|V)
    MEDIA_PATH="${MEDIA_DIR}/video_${TIMESTAMP}.mp4"
    if show_progress "$VIDEO_DURATION" "Recording video..." sudo -u "$ORIGINAL_USER" ffmpeg -y -f v4l2 -video_size "$RESOLUTION" -framerate "$VIDEO_FRAMERATE" -i "$VIDEO_DEVICE" -t "$VIDEO_DURATION" "$MEDIA_PATH"; then
        success "Video saved to: ${MEDIA_PATH}"
    else fail "Failed to record video."; fi
    ;;
  l|L)
    step "Starting Live View"
    info "A new window will open. To stop, press 'q' or close it."
    sudo -u "$ORIGINAL_USER" ffplay -f v4l2 -video_size "$RESOLUTION" -an -sn -window_title "Thermal Camera Live View" -i "$VIDEO_DEVICE" &>/dev/null
    success "Live view session ended."
    ;;
  *) fail "Invalid choice. Please run the script again.";;
esac

echo "--------------------------------------------------------"
info "Script finished."
ELAPSED_TIME=$(($SECONDS - $START_TIME))
step "elapsed time ${ELAPSED_TIME}s"
