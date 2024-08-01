#!/bin/bash

# Ensure necessary arguments are provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 DOWNLOAD_FOLDER"
    exit 1
fi

DOWNLOAD_FOLDER=$1

# Create the main script
cat <<EOF > ~/DataDownload.sh
#!/bin/bash

# Ensure necessary arguments are provided
if [ "\$#" -ne 1 ]; then
    echo "Usage: \$0 DOWNLOAD_FOLDER"
    exit 1
fi

DOWNLOAD_FOLDER=\$1

# URLs to download the data from
urls=(
    "https://services.swpc.noaa.gov/json/goes/primary/xrays-7-day.json"
    "https://services.swpc.noaa.gov/json/goes/secondary/xrays-7-day.json"
)

# Create directories if they don't exist
mkdir -p "\$DOWNLOAD_FOLDER/primary"
mkdir -p "\$DOWNLOAD_FOLDER/secondary"

# Function to download and save the JSON data
download_and_save_data() {
    url=\$1
    folder=\$2
    current_time=\$(date +"%Y%m%d_%H%M%S")
    file_path="\$folder/xrays-7-day_\$current_time.json"
    curl -s "\$url" -o "\$file_path"
}

# Download and save primary and secondary data
download_and_save_data "\${urls[0]}" "\$DOWNLOAD_FOLDER/primary"
download_and_save_data "\${urls[1]}" "\$DOWNLOAD_FOLDER/secondary"
EOF

# Make the main script executable
chmod +x ~/DataDownload.sh

# Check and update the cron job that runs every 5 days
(crontab -l 2>/dev/null | grep -v 'DataDownload.sh'; echo "0 0 */5 * * ~/DataDownload.sh $DOWNLOAD_FOLDER") | crontab -
