#!/bin/bash

# A script to auto-rotate the screen and input devices on a convertible laptop.
# This version dynamically finds device IDs from their names at launch and uses
# robust parsing to handle duplicate device names and complex hardware like styluses
# that register as multiple device types (pointer and keyboard).

# use>>>>
# mkdir -p ~/.config/systemd/user/
# nano ~/.config/systemd/user/auto-rotate.service
# [Unit]
# Description=Auto-rotate screen and input script

# [Service]
# ExecStart=/usr/local/bin/screen_auto_rotate_inputlock.sh
# Restart=always

# [Install]
# WantedBy=default.target
# ```*_(Note: Make sure `ExecStart` points to the correct, full path of your script)_*

# **4. Save and exit** the nano editor (`Ctrl+X`, `Y`, `Enter`).

# **5. Enable and start the service:**
# ```bash
# # Reload systemd to make it aware of the new file
# systemctl --user daemon-reload

# # Enable the service to start automatically on every login
# systemctl --user enable --now auto-rotate.service


# --- Configuration ---
# Define the unique names of the devices we need to control.
DISPLAY_OUTPUT="eDP"
TOUCHPAD_NAME="ELAN1201:00 04F3:3098 Touchpad"
# The stylus hardware registers as two devices. We need the raw name to find the correct one.
STYLUS_RAW_NAME="ELAN9008:00 04F3:2C82"
KEYBOARD_POINTER_NAME="pointer:Asus Keyboard"
KEYBOARD_RAW_NAME="Asus Keyboard"

# --- Dynamic Device ID Fetching ---
# Use xinput to find the current ID for each unique device.
TOUCHPAD_ID=$(xinput list --id-only "$TOUCHPAD_NAME")
KEYBOARD_POINTER_ID=$(xinput list --id-only "$KEYBOARD_POINTER_NAME")

# For the stylus, find the one that is a "slave pointer".
STYLUS_ID=$(xinput list | grep "$STYLUS_RAW_NAME" | grep "slave  pointer" | sed 's/.*id=\([0-9]*\).*/\1/')

# For the keyboards, find the ones that are "slave keyboard".
KEYBOARD_IDS=($(xinput list | grep "$KEYBOARD_RAW_NAME" | grep "slave  keyboard" | sed 's/.*id=\([0-9]*\).*/\1/'))

# --- Sanity Check ---
# Exit if any of the essential devices weren't found.
if [ -z "$TOUCHPAD_ID" ] || [ -z "$STYLUS_ID" ] || [ -z "$KEYBOARD_POINTER_ID" ]; then
    echo "Error: Could not find one or more required input devices (Touchpad, Stylus Pointer, or Keyboard Pointer). Exiting."
    xinput list # Print list for debugging
    exit 1
fi
if [ ${#KEYBOARD_IDS[@]} -eq 0 ]; then
    echo "Error: Could not find any physical keyboard devices ('Asus Keyboard'). Exiting."
    xinput list # Print list for debugging
    exit 1
fi


# --- Rotation Logic ---
function rotate_normal() {
    xrandr --output "$DISPLAY_OUTPUT" --rotate normal
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' 1 0 0 0 1 0 0 0 1
    xinput set-prop "$STYLUS_ID" 'Coordinate Transformation Matrix' 1 0 0 0 1 0 0 0 1
    xinput enable "$KEYBOARD_POINTER_ID"
    xinput enable "$TOUCHPAD_ID"
    for id in "${KEYBOARD_IDS[@]}"; do xinput enable "$id"; done
}

function rotate_left() {
    xrandr --output "$DISPLAY_OUTPUT" --rotate left
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1
    xinput set-prop "$STYLUS_ID" 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1
    xinput disable "$KEYBOARD_POINTER_ID"
    xinput disable "$TOUCHPAD_ID"
    for id in "${KEYBOARD_IDS[@]}"; do xinput disable "$id"; done
}

function rotate_right() {
    xrandr --output "$DISPLAY_OUTPUT" --rotate right
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
    xinput set-prop "$STYLUS_ID" 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
    xinput disable "$KEYBOARD_POINTER_ID"
    xinput disable "$TOUCHPAD_ID"
    for id in "${KEYBOARD_IDS[@]}"; do xinput disable "$id"; done
}

function rotate_inverted() {
    xrandr --output "$DISPLAY_OUTPUT" --rotate inverted
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1
    xinput set-prop "$STYLUS_ID" 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1
    xinput disable "$KEYBOARD_POINTER_ID"
    xinput disable "$TOUCHPAD_ID"
    for id in "${KEYBOARD_IDS[@]}"; do xinput disable "$id"; done
}

# --- Main Loop ---
echo "Starting auto-rotation script. Press Ctrl+C to stop."
echo "Found Touchpad ID: $TOUCHPAD_ID"
echo "Found Stylus Pointer ID: $STYLUS_ID"
echo "Found Keyboard Pointer ID: $KEYBOARD_POINTER_ID"
echo "Found Physical Keyboard IDs: ${KEYBOARD_IDS[*]}"

rotate_normal

monitor-sensor | while read -r line; do
    case "$line" in
        *"Accelerometer orientation changed: normal"*)
            echo "Orientation: Normal"
            rotate_normal ;;
        *"Accelerometer orientation changed: left-up"*)
            echo "Orientation: Left-Up"
            rotate_left ;;
        *"Accelerometer orientation changed: right-up"*)
            echo "Orientation: Right-Up"
            rotate_right ;;
        *"Accelerometer orientation changed: bottom-up"*)
            echo "Orientation: Bottom-Up (Inverted)"
            rotate_inverted ;;
    esac
done
