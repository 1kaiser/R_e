#!/bin/bash

# Ensure arguments are passed
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 REMOTE_USER REMOTE_HOST REMOTE_PATH REMOTE_PASS"
    exit 1
fi

REMOTE_USER=$1
REMOTE_HOST=$2
REMOTE_PATH=$3
REMOTE_PASS=$4

# Define variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILE_NAME="pi_zero_NoIR_$TIMESTAMP.jpg"
LOG_FILE="$HOME/transmission_log.txt"
SHUTTER=6000000 # (1 TO 6 SECONDS) X1000000
GAIN=16.0  # Adjust this value to control the ISO, typically ranges from 1.0 to 16.0
AWB="auto"  # Auto White Balance: auto, incandescent, tungsten, fluorescent, indoor, daylight, cloudy, custom
METERING="centre"  # Metering mode: centre, spot, average


# Capture the image with custom exposure settings
libcamera-still --width 0 --height 0 --shutter $SHUTTER --gain $GAIN --awb $AWB --metering $METERING -o $FILE_NAME

# Check if the capture was successful
if [ -f $FILE_NAME ]; then
    # Send the file over SSH using sshpass
    sshpass -p "$REMOTE_PASS" scp $FILE_NAME $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH

    # Check if the file was successfully sent
    if [ $? -eq 0 ]; then
        # Log the successful transmission
        echo "$TIMESTAMP - $FILE_NAME" >> $LOG_FILE
        # Delete the local file
        rm $FILE_NAME
    fi
fi
