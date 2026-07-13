# 🌡️📹 High-Performance Terminal Thermal Camera Stream

This directory contains high-performance tools to capture, process, and render real-time radiometric thermal imaging from a UVC thermal camera (such as Hikmicro or InfiRay) directly inside your terminal session at **25 FPS** (the camera's full hardware limit).

---

## 📂 File Architecture

* **`temp_cam.sh`**: Standalone Shell/Python script. Parses dynamic heights (`256x196` and `256x344` frames), crops metadata, rotates 90° CW, mirrors horizontally (L-R), and applies a true Ironbow color mapping.
* **`process.c`**: Highly optimized C implementation of the image processing pipeline. Compiles to WebAssembly (`process.wasm`).
* **`process.wasm`**: Compiled WebAssembly binary module. Performs the 192-row metadata cropping, 90° CW rotation, mirroring, normalization, and Ironbow LUT mapping in microseconds.
* **`live_thermal.js`**: Node.js stream runner. Captures a continuous stream from `/dev/video0` using `v4l2-ctl`, feeds it into WASM, and renders double-density truecolor half-blocks (`▄` / `▀`) with direct ANSI escape sequences to minimize terminal CPU load.
* **`package.json`**: Manifest configuration file to allow global `npm` installs and local execution shortcuts.

---

## ⚙️ Prerequisites

To run these scripts, your system needs:
1. **System packages**: `v4l-utils`, `node`, `npm`, `chafa`, `timg`
2. **Python packages** (for `temp_cam.sh` only): `python3-numpy`, `python3-pillow`

If run as root (`sudo`), `temp_cam.sh` will **automatically install all missing prerequisites** via apt.

---

## 🚀 Execution Guides

### Option 1: Standalone Image Capture (In-Memory Run)
Downloads the script dynamically, captures a single mirrored frame, saves it to `thermal_captures/color_thermal.png`, renders it, and cleans up immediately:
```bash
sudo bash -c "$(wget -qO- \
  https://raw.githubusercontent.com/1kaiser/R_e/main/thermal/temp_cam.sh)" \
  _ image 0 timg
```

### Option 2: Live Video Monitor Stream (In-Memory Run)
Launches the WebAssembly-accelerated live stream. Downloads the WASM binary and JS runner to `/tmp`, streams at 25 FPS, and deletes all files automatically upon pressing `Ctrl+C`:
```bash
(cd /tmp && \
  wget -q https://raw.githubusercontent.com/1kaiser/R_e/main/thermal/process.wasm && \
  wget -q https://raw.githubusercontent.com/1kaiser/R_e/main/thermal/live_thermal.js && \
  chmod +x live_thermal.js && sudo ./live_thermal.js; \
  rm -f process.wasm live_thermal.js)
```

### Option 3: Local Global Installation (Permanent Offline Command)
Installs the files globally on your machine so you can run the live thermal camera instantly, offline, and from any folder:
```bash
# Clone the repository
git clone https://github.com/1kaiser/R_e.git /tmp/R_e_install

# Install the subfolder package globally
sudo npm install -g /tmp/R_e_install/thermal

# Clean up installer folder
rm -rf /tmp/R_e_install
```
Once installed, simply run:
```bash
sudo live-thermal
```

---

## 🛠️ WebAssembly Compilation (Development)

If you modify the C processing logic in `process.c`, you can recompile the WASM binary using `clang`:

```bash
clang --target=wasm32 -O3 -nostdlib \
  -Wl,--no-entry \
  -Wl,--export=init_lut \
  -Wl,--export=process_frame \
  -Wl,--export=get_input_ptr \
  -Wl,--export=get_output_ptr \
  -o process.wasm process.c
```
