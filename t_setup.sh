#!/bin/bash

# Define the script URL and local path
SCRIPT_URL="https://raw.githubusercontent.com/1kaiser/R_e/main/t.py"
LOCAL_SCRIPT="t.py"

# Check if the script is already running
if ! pgrep -f "python $LOCAL_SCRIPT" > /dev/null; then
    # Download the script if it does not exist or update it
    wget -O "$LOCAL_SCRIPT" "$SCRIPT_URL"
    # Make sure the script is executable
    chmod +x "$LOCAL_SCRIPT"
    # Run the script
    python "$LOCAL_SCRIPT" &
fi
