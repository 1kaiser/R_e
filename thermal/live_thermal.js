#!/usr/bin/env node

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// 1. Load WASM Module
const wasmPath = path.join(__dirname, 'process.wasm');
if (!fs.existsSync(wasmPath)) {
  console.error("Error: process.wasm not found. Please compile process.c first.");
  process.exit(1);
}

const wasmBuffer = fs.readFileSync(wasmPath);
const wasmModule = new WebAssembly.Module(wasmBuffer);
const wasmInstance = new WebAssembly.Instance(wasmModule, {});

const { init_lut, process_frame, get_input_ptr, get_output_ptr, memory } = wasmInstance.exports;

// Initialize colormap LUT in WASM
init_lut();

const inputPtr = get_input_ptr();
const outputPtr = get_output_ptr();

const INPUT_WIDTH = 256;
const INPUT_HEIGHT = 344;
const FRAME_BYTES = INPUT_WIDTH * INPUT_HEIGHT * 2; // 176128 bytes

const OUT_WIDTH = 192;
const OUT_HEIGHT = 256;

const inputView = new Uint16Array(memory.buffer, inputPtr, INPUT_WIDTH * INPUT_HEIGHT);
const outputView = new Uint8Array(memory.buffer, outputPtr, OUT_HEIGHT * OUT_WIDTH * 3);

// 2. Setup Terminal Rendering parameters
let termWidth = process.stdout.columns || 80;
let termHeight = process.stdout.rows || 24;

// Listen for terminal resize
process.stdout.on('resize', () => {
  termWidth = process.stdout.columns || 80;
  termHeight = process.stdout.rows || 24;
});

// Hide cursor and clear terminal at start
process.stdout.write('\x1b[?25l\x1b[2J');

function cleanup() {
  // Restore cursor and reset terminal formatting
  process.stdout.write('\x1b[?25h\x1b[0m\n');
  process.exit(0);
}

process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

// 3. Start Camera Capture Subprocess
// We configure format first
const setupNode = spawn('v4l2-ctl', [
  '-d', '/dev/video0',
  '--set-fmt-video=width=256,height=344,pixelformat=YUYV'
]);

setupNode.on('close', () => {
  // Start continuous stream
  const camera = spawn('v4l2-ctl', [
    '-d', '/dev/video0',
    '--stream-mmap',
    '--stream-to=-'
  ]);

  let accumBuffer = Buffer.alloc(0);
  let fpsCounter = 0;
  let lastFpsTime = Date.now();
  let currentFps = 0;

  camera.stdout.on('data', (chunk) => {
    accumBuffer = Buffer.concat([accumBuffer, chunk]);

    while (accumBuffer.length >= FRAME_BYTES) {
      const frameData = accumBuffer.subarray(0, FRAME_BYTES);
      accumBuffer = accumBuffer.subarray(FRAME_BYTES);

      // Process and render frame
      renderFrame(frameData);
      
      // FPS tracking
      fpsCounter++;
      const now = Date.now();
      if (now - lastFpsTime >= 1000) {
        currentFps = fpsCounter;
        fpsCounter = 0;
        lastFpsTime = now;
      }
    }
  });

  camera.stderr.on('data', (data) => {
    // Suppress or print driver errors
  });

  camera.on('close', () => {
    cleanup();
  });

  function renderFrame(rawBuffer) {
    // Copy raw frame bytes directly into WASM input buffer (convert uint8 to uint16)
    const uint16View = new Uint16Array(
      rawBuffer.buffer,
      rawBuffer.byteOffset,
      INPUT_WIDTH * INPUT_HEIGHT
    );
    inputView.set(uint16View);

    // Run WASM processing
    process_frame();

    // Calculate dynamic scaling to fit terminal
    const maxW = termWidth - 2;
    const maxH = (termHeight - 3) * 2;
    const scale = Math.min(maxW / OUT_WIDTH, maxH / OUT_HEIGHT);
    const dstW = Math.floor(OUT_WIDTH * scale);
    const dstH = Math.floor(OUT_HEIGHT * scale);

    // Build frame output string
    let out = '\x1b[H'; // Move cursor to top-left (flicker-free redraw)
    out += `\x1b[1;32m📡 WASM Live Thermal Stream | FPS: ${currentFps} | Terminal: ${termWidth}x${termHeight} | Ctrl+C to Exit\x1b[0m\n`;

    // Render using half-block characters
    for (let y = 0; y < dstH; y += 2) {
      let line = '';
      for (let x = 0; x < dstW; x++) {
        const srcCol = Math.min(OUT_WIDTH - 1, Math.floor(x / scale));
        
        // Top pixel
        const srcRow1 = Math.min(OUT_HEIGHT - 1, Math.floor(y / scale));
        const idx1 = (srcRow1 * OUT_WIDTH + srcCol) * 3;
        const r1 = outputView[idx1];
        const g1 = outputView[idx1 + 1];
        const b1 = outputView[idx1 + 2];

        // Bottom pixel
        const srcRow2 = Math.min(OUT_HEIGHT - 1, Math.floor((y + 1) / scale));
        const idx2 = (srcRow2 * OUT_WIDTH + srcCol) * 3;
        const r2 = outputView[idx2];
        const g2 = outputView[idx2 + 1];
        const b2 = outputView[idx2 + 2];

        // ANSI escape sequence
        line += `\x1b[48;2;${r1};${g1};${b1}m\x1b[38;2;${r2};${g2};${b2}m▄`;
      }
      out += line + '\x1b[0m\n';
    }

    process.stdout.write(out);
  }
});
