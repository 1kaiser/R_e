#!/bin/bash

# A script to auto-rotate the screen and input devices on a convertible laptop.
#
# INSTRUCTIONS:
# 1. Save this script to a file, for example: ~/auto-rotate-input.sh
# 2. Make it executable: chmod +x ~/auto-rotate-input.sh
# 3. Find your primary display name by running the `xrandr` command.
#    Look for the output that says "connected primary" (e.g., "eDP", "LVDS1").
#    Update the DISPLAY_OUTPUT variable below if yours is different.
# 4. Run the script with root privileges: sudo ~/auto-rotate-input.sh

# --- Configuration ---
# Set your primary display output here. This has been corrected for your system.
DISPLAY_OUTPUT="eDP"

# Device IDs from `xinput list`.
# It's better to disable all potential keyboards and pointers to be safe.
TOUCHPAD_ID=16
STYLUS_PEN_ID=19
STYLUS_ERASER_ID=20
KEYBOARD_POINTER_ID=10 # "Asus Keyboard" that acts as a pointer
KEYBOARD_ID_1=11       # "Asus Keyboard"
KEYBOARD_ID_2=18       # "Asus Keyboard"

# --- Rotation Logic ---

# Function to apply transformations for "normal" orientation
function rotate_normal() {
    # Rotate the screen
    xrandr --output "$DISPLAY_OUTPUT" --rotate normal

    # Set transformation matrix for pointer devices
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' 1 0 0 0 1 0 0 0 1
    xinput set-prop "$STYLUS_PEN_ID" 'Coordinate Transformation Matrix' 1 0 0 0 1 0 0 0 1
    xinput set-prop "$STYLUS_ERASER_ID" 'Coordinate Transformation Matrix' 1 0 0 0 1 0 0 0 1

    # Enable keyboards and touchpad for laptop mode
    xinput enable "$KEYBOARD_POINTER_ID"
    xinput enable "$KEYBOARD_ID_1"
    xinput enable "$KEYBOARD_ID_2"
    xinput enable "$TOUCHPAD_ID"
}

# Function to apply transformations for "left-up" orientation
function rotate_left() {
    # Rotate the screen
    xrandr --output "$DISPLAY_OUTPUT" --rotate left

    # Set transformation matrix for pointer devices
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1
    xinput set-prop "$STYLUS_PEN_ID" 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1
    xinput set-prop "$STYLUS_ERASER_ID" 'Coordinate Transformation Matrix' 0 -1 1 1 0 0 0 0 1

    # Disable physical keyboard and touchpad for tablet mode
    xinput disable "$KEYBOARD_POINTER_ID"
    xinput disable "$KEYBOARD_ID_1"
    xinput disable "$KEYBOARD_ID_2"
    xinput disable "$TOUCHPAD_ID"
}

# Function to apply transformations for "right-up" orientation
function rotate_right() {
    # Rotate the screen
    xrandr --output "$DISPLAY_OUTPUT" --rotate right

    # Set transformation matrix for pointer devices
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
    xinput set-prop "$STYLUS_PEN_ID" 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
    xinput set-prop "$STYLUS_ERASER_ID" 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1

    # Disable physical keyboard and touchpad for tablet mode
    xinput disable "$KEYBOARD_POINTER_ID"
    xinput disable "$KEYBOARD_ID_1"
    xinput disable "$KEYBOARD_ID_2"
    xinput disable "$TOUCHPAD_ID"
}

# Function to apply transformations for "bottom-up" (inverted) orientation
function rotate_inverted() {
    # Rotate the screen
    xrandr --output "$DISPLAY_OUTPUT" --rotate inverted

    # Set transformation matrix for pointer devices
    xinput set-prop "$TOUCHPAD_ID" 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1
    xinput set-prop "$STYLUS_PEN_ID" 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1
    xinput set-prop "$STYLUS_ERASER_ID" 'Coordinate Transformation Matrix' -1 0 1 0 -1 1 0 0 1

    # Disable physical keyboard and touchpad for tablet mode
    xinput disable "$KEYBOARD_POINTER_ID"
    xinput disable "$KEYBOARD_ID_1"
    xinput disable "$KEYBOARD_ID_2"
    xinput disable "$TOUCHPAD_ID"
}


# --- Main Loop ---
# Monitor sensor changes and call the appropriate function.
echo "Starting auto-rotation script. Press Ctrl+C to stop."

# Set initial orientation
rotate_normal

monitor-sensor | while read -r line; do
    case "$line" in
        *"Accelerometer orientation changed: normal"*)
            echo "Orientation: Normal"
            rotate_normal
            ;;
        *"Accelerometer orientation changed: left-up"*)
            echo "Orientation: Left-Up"
            rotate_left
            ;;
        *"Accelerometer orientation changed: right-up"*)
            echo "Orientation: Right-Up"
            rotate_right
            ;;
        *"Accelerometer orientation changed: bottom-up"*)
            echo "Orientation: Bottom-Up (Inverted)"
            rotate_inverted
            ;;
    esac
done
