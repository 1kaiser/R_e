#!/bin/bash

# Ensure necessary arguments are provided
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 REMOTE_USER REMOTE_HOST REMOTE_PATH PASSWORD GITHUB_REPO"
    exit 1
fi

REMOTE_USER=$1
REMOTE_HOST=$2
REMOTE_PATH=$3
PASSWORD=$4
GITHUB_REPO=$5

# Install expect and sshpass if not already installed
if ! command -v expect &> /dev/null
then
    sudo apt-get update
    sudo apt-get install -y expect
fi

if ! command -v sshpass &> /dev/null
then
    sudo apt-get install -y sshpass
fi

# Create the main script
cat <<EOF > ~/SnapSend.sh
#!/bin/bash

if [ "\$#" -ne 4 ]; then
    echo "Usage: \$0 REMOTE_USER REMOTE_HOST REMOTE_PATH PASSWORD"
    exit 1
fi

REMOTE_USER=\$1
REMOTE_HOST=\$2
REMOTE_PATH=\$3
PASSWORD=\$4

# Define variables
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
FILE_NAME="\$HOME/pi_zero_NoIR_\$TIMESTAMP.jpg"
LOG_FILE="\$HOME/transmission_log.txt"
SHUTTER=6000000 # (1 TO 6 SECONDS) X1000000
GAIN=4.0  # Adjust this value to control the ISO, typically ranges from 1.0 to 16.0
AWB="auto"  # Auto White Balance: auto, incandescent, tungsten, fluorescent, indoor, daylight, cloudy, custom
METERING="centre"  # Metering mode: centre, spot, average
FOCUS_MODE="manual" 
XX=0


# Capture the image with custom exposure settings
libcamera-still --width 0 --height 0 --shutter \$SHUTTER --gain \$GAIN --awb \$AWB --metering \$METERING --lens-position \$XX --autofocus-mode \$FOCUS_MODE -o \$FILE_NAME

if [ -f \$FILE_NAME ]; then
    sshpass -p "\$PASSWORD" scp \$FILE_NAME \$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_PATH
    if [ \$? -eq 0 ]; then
        echo "\$TIMESTAMP - \$FILE_NAME" >> \$LOG_FILE
        rm \$FILE_NAME
    fi
fi
EOF

# Make the main script executable
chmod +x ~/SnapSend.sh

# Function to download SnapSend.sh if it does not exist
download_snapsend() {
    if [ ! -f ~/SnapSend.sh ]; then
        wget -O ~/SnapSend.sh https://raw.githubusercontent.com/$GITHUB_REPO/main/SnapSend.sh
        chmod +x ~/SnapSend.sh
    fi
}

# Add the cron jobs
(crontab -l 2>/dev/null; echo "@reboot bash -c 'if ! pgrep -f SnapSend.sh > /dev/null; then download_snapsend && ~/SnapSend.sh $REMOTE_USER $REMOTE_HOST $REMOTE_PATH '$PASSWORD'; fi'") | crontab -
(crontab -l 2>/dev/null; echo "*/1 * * * * bash -c 'if ! pgrep -f SnapSend.sh > /dev/null; then download_snapsend && ~/SnapSend.sh $REMOTE_USER $REMOTE_HOST $REMOTE_PATH '$PASSWORD'; fi'") | crontab -
