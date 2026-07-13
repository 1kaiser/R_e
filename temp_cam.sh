#!/bin/bash

# --- Default Hardcoded Parameter Configurations ---
OUTPUT_DIR="thermal_captures"
RAW_BIN="$OUTPUT_DIR/raw_frame.bin"
COLOR_PNG="$OUTPUT_DIR/color_thermal.png"
DEVICE_RETRY_SECS=5

# ANSI Screen Typography Accents
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO] $1${NC}" >&2; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}" >&2; }
fail() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# --- 1. Pre-Flight Subsystem Validation ---
check_dependencies() {
    local missing_apts=()

    # 1. Binary checks
    if ! command -v v4l2-ctl &>/dev/null; then
        missing_apts+=("v4l-utils")
    fi
    # We require either chafa or timg to be present
    if ! command -v chafa &>/dev/null && ! command -v timg &>/dev/null; then
        missing_apts+=("chafa" "timg")
    fi
    if ! command -v python3 &>/dev/null; then
        missing_apts+=("python3")
    fi

    # 2. Python module checks
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import numpy" &>/dev/null; then
            missing_apts+=("python3-numpy")
        fi
        if ! python3 -c "import PIL" &>/dev/null; then
            missing_apts+=("python3-pillow")
        fi
    fi

    if [ ${#missing_apts[@]} -ne 0 ]; then
        warn "Missing system dependencies: ${missing_apts[*]}"
        if [ "$EUID" -eq 0 ] && command -v apt-get &>/dev/null; then
            info "Running as root. Attempting to install missing dependencies automatically..."
            apt-get update -qq
            apt-get install -y "${missing_apts[@]}"
            if [ $? -eq 0 ]; then
                info "Dependencies installed successfully!"
                return 0
            fi
        fi
        fail "Please install dependencies manually: sudo apt update && sudo apt install -y ${missing_apts[*]}"
    fi
}

# --- 2. Intelligent Non-Destructive Driver Safeguard ---
verify_driver_state() {
    if [ -f /sys/module/uvcvideo/parameters/quirks ]; then
        local live_quirks=$(cat /sys/module/uvcvideo/parameters/quirks)
        if [ "$live_quirks" -eq 2 ]; then
            return 0 # Subsystem already patched; skip dynamic reloads
        fi
    fi
    
    echo "--------------------------------------------------------" >&2
    info "Live kernel driver parameters unpatched. Aligning quirks layer configuration..."
    if [ ! -f /etc/modprobe.d/uvcvideo-hik.conf ]; then
        echo "options uvcvideo quirks=2" | sudo tee /etc/modprobe.d/uvcvideo-hik.conf > /dev/null
    fi
    sudo rmmod uvcvideo 2>/dev/null || warn "Kernel space driver active. If device fails, execute a warm reboot."
    sudo modprobe uvcvideo quirks=2 2>/dev/null
    echo "--------------------------------------------------------" >&2
}

# --- 3. Dynamic Device Endpoint Auto-Discovery ---
resolve_hardware_node() {
    local manual_override="$1"
    if [ -n "$manual_override" ] && [ -c "$manual_override" ]; then
        echo "$manual_override"
        return 0
    fi

    local waited=0
    while [ $waited -lt $DEVICE_RETRY_SECS ]; do
        local detected_node=$(v4l2-ctl --list-devices 2>/dev/null | grep -A2 -E "UVC Camera|Camera" | grep -oP '/dev/video\d+' | head -1)
        if [ -n "$detected_node" ] && [ -c "$detected_node" ]; then
            echo "$detected_node"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# --- 4. Core Radiometric Buffer Demuxer Execution Unit ---
capture_and_render_frame() {
    local dev="$1"
    local sym="$2"
    local ts_flag="$3"

    # Pull uncompressed byte payload directly off microbolometer registers
    # Note: We try to set format, but some drivers/kernel setups refuse dynamic format change and stay at default 256x344
    v4l2-ctl -d "$dev" --set-fmt-video=width=256,height=196,pixelformat=YUYV --stream-mmap --stream-to="$RAW_BIN" --stream-count=1 &>/dev/null
    
    if [ ! -s "$RAW_BIN" ]; then
        warn "Hardware tracking buffer empty. Data bus pipe stalled."
        return 1
    fi

    # Synchronous Python Data Parsing Engine Block (Dynamically handles 256x196 and 256x344 fallbacks)
    python3 -c "
import sys, os
import numpy as np
from PIL import Image

try:
    if not os.path.exists('$RAW_BIN'): sys.exit(1)
    
    raw_stream = np.fromfile('$RAW_BIN', dtype=np.uint16)
    num_elements = len(raw_stream)
    width = 256
    height = num_elements // width
    
    matrix = raw_stream[:height*width].reshape((height, width))
    
    # Slice off metadata rows depending on the mode
    if height == 196:
        thermal_pixels = matrix[:192, :].astype(float)
    elif height == 344:
        thermal_pixels = matrix[:320, :].astype(float)
    else:
        thermal_pixels = matrix[:(height - height % 8), :].astype(float)
    
    p_min, p_max = thermal_pixels.min(), thermal_pixels.max()
    norm = (thermal_pixels - p_min) / (p_max - p_min) if p_max > p_min else np.zeros_like(thermal_pixels)
        
    R = np.clip(1.5 * norm, 0.0, 1.0)
    G = np.clip(2.0 * norm - 0.5, 0.0, 1.0)
    B = np.clip(4.0 * (1.0 - norm), 0.0, 1.0)
    
    rgb_canvas = (np.dstack((R, G, B)) * 255.0).astype(np.uint8)
    Image.fromarray(rgb_canvas, mode='RGB').save('$COLOR_PNG')
except Exception as e:
    print(f'Engine Failure: {e}', file=sys.stderr)
    sys.exit(1)
"
    if [ $? -ne 0 ]; then
        warn "Python transformation layout corrupted."
        return 1
    fi

    # Handle conditional high-precision timestamp archival copy
    if [ "$ts_flag" = "1" ]; then
        local ts_filename="$OUTPUT_DIR/thermal_$(date +%Y%m%d_%H%M%S_%3N).png"
        cp "$COLOR_PNG" "$ts_filename"
        info "Archived frame copy safely preserved at: $ts_filename"
    fi

    # Project false-color grid straight into active terminal session window
    render_image "$COLOR_PNG" "$sym"
    return 0
}

# Dynamic terminal rendering utility selector
render_image() {
    local img="$1"
    local sym="$2"

    if [ "$sym" = "timg" ] && command -v timg &>/dev/null; then
        timg "$img"
    elif command -v chafa &>/dev/null; then
        local chafa_sym="$sym"
        if [ "$chafa_sym" = "timg" ]; then chafa_sym="block"; fi
        chafa --symbols "$chafa_sym" "$img"
    elif command -v timg &>/dev/null; then
        timg "$img"
    else
        warn "No terminal rendering utility (chafa or timg) available."
    fi
}

usage() {
    echo "⚙️  Turnkey Thermal Subsystem Terminal Controller Engine"
    echo "Usage: $0 [action: image|loop] [interval_seconds] [chafa_symbols|timg] [device_path] [save_timestamp: 0|1]"
    echo ""
    echo "Positional Parameter Configurations:"
    echo "  interval_seconds  : Cycle pause length (Defaults to 2s. Accepts decimals like 0.2)"
    echo "  chafa_symbols|timg: Render block shapes (block, quad, sex, braille, all, or timg. Default: block)"
    echo "  device_path       : Absolute video endpoint node (Auto-resolved if omitted)"
    echo "  save_timestamp    : Archive image file with precise timestamps (0=Off, 1=On. Default: 0)"
    echo ""
    echo "Production Usage Map Examples:"
    echo "  sudo $0 image 0 timg /dev/video0 1   <- Snaps a single frame using timg AND saves copy"
    echo "  sudo $0 loop 2 quad /dev/video0 1    <- Activates live view with chafa quad blocks"
    exit 1
}

# --- 5. Main Execution Routing Gateways ---
check_dependencies
verify_driver_state

ACTION="${1:-image}"
INTERVAL="${2:-2}"
SYMBOLS="${3:-block}"
MANUAL_NODE_ARG="$4"
SAVE_TIMESTAMP="${5:-0}"

if [ "$ACTION" != "image" ] && [ "$ACTION" != "loop" ]; then
    usage
fi

# Resolve physical hardware tracking maps
TARGET_DEVICE=$(resolve_hardware_node "$MANUAL_NODE_ARG")
if [ -z "$TARGET_DEVICE" ] || [ ! -c "$TARGET_DEVICE" ]; then
    fail "Critical Link Fault: Could not capture or resolve camera descriptor path structures."
fi

mkdir -p "$OUTPUT_DIR"

case "$ACTION" in
    image)
        info "Snapping singular radiometric thermal frame via [$TARGET_DEVICE] (Mode: $SYMBOLS)..."
        capture_and_render_frame "$TARGET_DEVICE" "$SYMBOLS" "$SAVE_TIMESTAMP" || fail "Singular image engine capture crash."
        ;;
        
    loop)
        info "Spawning continuous monitoring loops (Interval: ${INTERVAL}s | Mode: $SYMBOLS)..."
        [ "$SAVE_TIMESTAMP" = "1" ] && warn "Timelapse archival enabled! Writing frames continuously to local storage directory."
        info "To decouple from the live camera stream pipeline, hit [Ctrl + C]."
        sleep 1.5
        
        while true; do
            clear # Scrub terminal space completely for seamless frame placement
            echo -e "${GREEN}📡 Live Thermal Engine Matrix | Refresh: ${INTERVAL}s | Node: $TARGET_DEVICE | Archive: $SAVE_TIMESTAMP | Cancel: Ctrl+C${NC}"
            capture_and_render_frame "$TARGET_DEVICE" "$SYMBOLS" "$SAVE_TIMESTAMP"
            sleep "$INTERVAL"
        done
        ;;
esac
