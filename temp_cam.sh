#!/bin/bash

# A universal script to initialize a UVC thermal camera that automatically
# detects the Linux distribution and uses the native package manager.
# Includes an ASCII art live view mode for terminals.

# --- Configuration ---
VIDEO_DEVICE="/dev/video2"
RESOLUTION="256x196"
REQUIRED_QUIRK_VALUE="2"
MEDIA_DIR="media_TH"
VIDEO_DURATION=10
VIDEO_FRAMERATE=25
# --- NEW: ASCII view settings ---
ASCII_WIDTH=100 # Terminal columns for the view
ASCII_GAMMA=0.7 # Image gamma correction for better contrast

# --- Package to Command Mapping ---
# We now use an associative array for more complex dependencies.
declare -A REQUIRED_PACKAGES
REQUIRED_PACKAGES=(
    ["fswebcam"]="fswebcam"
    ["ffmpeg"]="ffmpeg"
    ["caca-utils"]="img2txt" # The 'img2txt' command is in the 'caca-utils' package (or 'libcaca' on Arch)
)
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
#  OS-AWARE PACKAGE MANAGEMENT FUNCTIONS (now uses the array)
# =============================================================================
OS_ID=""; IS_PKG_INSTALLED_CMD=""; PKG_INSTALL_CMD=""
function detect_os_and_set_commands {
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_ID=$ID; else fail "Cannot detect Linux distribution."; fi
    case "$OS_ID" in
        ubuntu|debian|mint|raspbian)
            IS_PKG_INSTALLED_CMD="dpkg-query -W -f='\${Status}' \"\$1\" 2>/dev/null | grep -q 'install ok installed'"
            PKG_INSTALL_CMD="apt-get update > /dev/null && apt-get install -y"
            ;;
        fedora|centos|rhel|rocky)
            IS_PKG_INSTALLED_CMD="rpm -q \"\$1\" &>/dev/null"
            PKG_INSTALL_CMD="dnf install -y"
            ;;
        arch|manjaro)
            # On Arch, the package for img2txt is just 'libcaca'
            REQUIRED_PACKAGES["libcaca"]="img2txt"
            unset REQUIRED_PACKAGES["caca-utils"]
            IS_PKG_INSTALLED_CMD="pacman -Q \"\$1\" &>/dev/null"
            PKG_INSTALL_CMD="pacman -S --noconfirm"
            ;;
        *) fail "Unsupported Linux distribution: $OS_ID.";;
    esac
    info "Detected '$OS_ID' distribution."
}
function is_package_installed { eval "$IS_PKG_INSTALLED_CMD"; }
function install_packages { info "Installing with '$OS_ID' native package manager..."; if ! $PKG_INSTALL_CMD "$@"; then fail "Failed to install packages: $@."; fi; }

# =============================================================================
#  SCRIPT STARTS HERE
# =============================================================================
START_TIME=$SECONDS
detect_os_and_set_commands

if [[ $EUID -ne 0 ]]; then
    step "Performing non-privileged pre-flight checks..."
    # (Pre-flight checks remain the same)
    NEEDS_SUDO=false
    for pkg in "${!REQUIRED_PACKAGES[@]}"; do
        if ! command -v "${REQUIRED_PACKAGES[$pkg]}" &> /dev/null; then
            info "Command '${REQUIRED_PACKAGES[$pkg]}' for package '$pkg' not found. Installation will require sudo."
            NEEDS_SUDO=true
        fi
    done
    if [ "$NEEDS_SUDO" = false ]; then success "All required packages are already installed."; fi
    echo "--------------------------------------------------------"
    ensure_root "$@"
fi

# =============================================================================
#  ROOT-PRIVILEGE SECTION
# =============================================================================
step "Running setup tasks with root privileges"

PACKAGES_TO_INSTALL=()
for pkg in "${!REQUIRED_PACKAGES[@]}"; do
    if ! command -v "${REQUIRED_PACKAGES[$pkg]}" &>/dev/null; then
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    info "Missing packages: ${PACKAGES_TO_INSTALL[*]}"
    install_packages "${PACKAGES_TO_INSTALL[@]}"
else
    success "All required packages were already installed."
fi

info "Reloading uvcvideo module with quirks=${REQUIRED_QUIRK_VALUE}..."
# (Driver logic remains the same)
modprobe -r uvcvideo &>/dev/null || true
if ! modprobe uvcvideo quirks=${REQUIRED_QUIRK_VALUE}; then fail "Failed to load uvcvideo module."; fi
current_quirk=$(cat /sys/module/uvcvideo/parameters/quirks)
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

read -p "Camera is ready. Take an (i)mage, (v)ideo, (l)ive view, or (a)scii live view? [i/v/l/a]: " choice

TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

case "$choice" in
  i|I) # ... Image capture ...
    ;;
  v|V) # ... Video capture ...
    ;;
  l|L) # ... Graphical Live view ...
    ;;

  a|A|ascii)
    step "Starting ASCII Live View"
    info "Press CTRL+C to stop the feed."
    sleep 2

    # This command traps the EXIT signal (like from Ctrl+C) and runs 'clear'
    # to ensure the terminal is cleaned up properly.
    trap 'clear; echo -e "${GREEN}ASCII view stopped.${NC}"' INT TERM

    # The main loop for ASCII view
    while true; do
        # Position the cursor at the top-left of the terminal
        echo -ne "\033[0;0H"
        
        # The pipeline:
        # ffmpeg grabs one frame, converts it to a simple PPM image, and pipes it to stdout.
        # img2txt reads the image from stdin, converts it to colored ASCII, and prints it.
        sudo -u "$ORIGINAL_USER" ffmpeg -loglevel quiet -i "$VIDEO_DEVICE" -vframes 1 -f image2pipe -vcodec ppm - \
        | img2txt -W "$ASCII_WIDTH" --gamma="$ASCII_GAMMA" -
        
        # A small sleep can help prevent 100% CPU usage on very fast systems.
        sleep 0.05
    done
    ;;

  *) fail "Invalid choice. Please run the script again.";;
esac

echo "--------------------------------------------------------"
info "Script finished."
ELAPSED_TIME=$(($SECONDS - $START_TIME))
step "elapsed time ${ELAPSED_TIME}s"
