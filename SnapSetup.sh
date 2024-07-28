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
sudo apt-get update
sudo apt-get install -y expect sshpass

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

# Define parameter arrays
SHUTTERS=(100 1000 10000 100000 1000000 10000000 50000000 112000000)
GAINS=(1.0 4.0 16.0)
AWBS=("auto")
METERINGS=("centre")

# Loop over all parameter combinations
for SHUTTER in "\${SHUTTERS[@]}"; do
    for GAIN in "\${GAINS[@]}"; do
        for AWB in "\${AWBS[@]}"; do
            for METERING in "\${METERINGS[@]}"; do

                # Define variables
                TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
                FILE_NAME_HDR="\$HOME/NoIR_HDR_\${TIMESTAMP}_s_\${SHUTTER}_g_\${GAIN}.jpg"
                RAW_FILE_NAME_HDR="\$HOME/NoIR_HDR_\${TIMESTAMP}_s_\${SHUTTER}_g_\${GAIN}.dng"
                FILE_NAME="\$HOME/NoIR_\${TIMESTAMP}_s_\${SHUTTER}_g_\${GAIN}.jpg"
                RAW_FILE_NAME="\$HOME/NoIR_\${TIMESTAMP}_s_\${SHUTTER}_g_\${GAIN}.dng"
                LOG_FILE="\$HOME/transmission_log.txt"

                # Capture the image with custom exposure settings (HDR)
                libcamera-still --width 0 --height 0 --shutter \$SHUTTER --gain \$GAIN --awb \$AWB --metering \$METERING --autofocus-mode auto --hdr -o \$FILE_NAME_HDR --raw 1
                # Delay for 3 seconds
                sleep 3
                
                # Upload the HDR JPEG image
                if [ -f \$FILE_NAME_HDR ]; then
                    sshpass -p "\$PASSWORD" scp \$FILE_NAME_HDR \$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_PATH
                    if [ \$? -eq 0 ]; then
                        echo "\$TIMESTAMP - \$FILE_NAME_HDR" >> \$LOG_FILE
                        rm \$FILE_NAME_HDR
                    fi
                fi

                # Upload the HDR DNG image
                if [ -f \$RAW_FILE_NAME_HDR ]; then
                    sshpass -p "\$PASSWORD" scp \$RAW_FILE_NAME_HDR \$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_PATH
                    if [ \$? -eq 0 ]; then
                        echo "\$TIMESTAMP - \$RAW_FILE_NAME_HDR" >> \$LOG_FILE
                        rm \$RAW_FILE_NAME_HDR
                    fi
                fi

                # Capture the image with custom exposure settings (non-HDR)
                libcamera-still --width 0 --height 0 --shutter \$SHUTTER --gain \$GAIN --awb \$AWB --metering \$METERING --autofocus-mode auto -o \$FILE_NAME --raw 1
                # Delay for 3 seconds
                sleep 3

                
                # Upload the non-HDR JPEG image
                if [ -f \$FILE_NAME ]; then
                    sshpass -p "\$PASSWORD" scp \$FILE_NAME \$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_PATH
                    if [ \$? -eq 0 ]; then
                        echo "\$TIMESTAMP - \$FILE_NAME" >> \$LOG_FILE
                        rm \$FILE_NAME
                    fi
                fi

                # Upload the non-HDR DNG image
                if [ -f \$RAW_FILE_NAME ]; then
                    sshpass -p "\$PASSWORD" scp \$RAW_FILE_NAME \$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_PATH
                    if [ \$? -eq 0 ]; then
                        echo "\$TIMESTAMP - \$RAW_FILE_NAME" >> \$LOG_FILE
                        rm \$RAW_FILE_NAME
                    fi
                fi

            done
        done
    done
done
EOF

# Make the main script executable
chmod +x ~/SnapSend.sh

# Add cron jobs to run after reboot and every minute
(crontab -l 2>/dev/null | grep -v 'SnapSend.sh'; echo "*/10 * * * * ~/SnapSend.sh $REMOTE_USER $REMOTE_HOST $REMOTE_PATH '$PASSWORD'") | crontab -
