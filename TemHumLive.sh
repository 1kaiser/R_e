#!/bin/bash

# Live Time Series ASCII Plotter (Functional/Stream-based approach)
# Uses a single AWK process to "map" data to a plot grid
# Press Ctrl+C to exit gracefully

# Handle Ctrl+C gracefully
trap 'echo -e "\n\nExiting live monitoring..."; cleanup; exit 0' INT

# Cleanup function
cleanup() {
    rm -f /tmp/plot_data_* 2>/dev/null
    tput cnorm  # Show cursor
}

# Function to display usage
usage() {
    echo "Usage: $0 <filename.csv> [options]"
    echo "Options:"
    echo "  -w WIDTH      Plot width in characters (default: 80)"
    echo "  -h HEIGHT     Plot height in lines (default: 20)"
    echo "  -n POINTS     Number of recent data points to display (default: 60)"
    echo "  -r REFRESH    Refresh interval in seconds (default: 5)"
    echo ""
    echo "Expected CSV format: timestamp,temperature,humidity"
    echo ""
    echo "Press Ctrl+C to exit live monitoring mode"
    exit 1
}

# Default values
PLOT_WIDTH=80
PLOT_HEIGHT=20
DATA_POINTS=60
REFRESH_INTERVAL=5
CSV_FILE=""

# Parse command line arguments (This part remains the same)
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--width) PLOT_WIDTH="$2"; shift 2 ;;
        -h|--height) PLOT_HEIGHT="$2"; shift 2 ;;
        -n|--points) DATA_POINTS="$2"; shift 2 ;;
        -r|--refresh) REFRESH_INTERVAL="$2"; shift 2 ;;
        -*) echo "Unknown option: $1"; usage ;;
        *)
            if [[ -z "$CSV_FILE" ]]; then CSV_FILE="$1"; else echo "Error: Multiple files not supported"; usage; fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CSV_FILE" ]]; then echo "Error: No CSV file specified"; usage; fi
if [[ ! -f "$CSV_FILE" ]]; then echo "Error: File '$CSV_FILE' not found"; exit 1; fi

# Function to extract and clean data (remains the same)
extract_recent_data() {
    local temp_file="/tmp/plot_data_$$"
    tail -n "$((DATA_POINTS + 10))" "$CSV_FILE" | sed 's/\r$//' | \
    awk -F',' 'BEGIN {OFS=","} {if (NR == 1 && (tolower($1) ~ /timestamp/ || tolower($2) ~ /temperature/)) next; gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3); if (NF >= 3 && $2 ~ /^-?[0-9]+\.?[0-9]*$/ && $3 ~ /^-?[0-9]+\.?[0-9]*$/) {print $1, $2, $3}}' | \
    tail -n "$DATA_POINTS" > "$temp_file"
    echo "$temp_file"
}

# --- REFACTORED PLOTTING FUNCTION ---
# This function now uses a single, powerful AWK command to perform all logic.
draw_timeseries_plot() {
    local data_file="$1"
    
    if [[ ! -s "$data_file" ]]; then
        echo "No data available"; return
    fi
    
    # Read the first and last timestamp from the file for the header
    local start_time=$(head -n 1 "$data_file" | cut -d',' -f1)
    local end_time=$(tail -n 1 "$data_file" | cut -d',' -f1)
    
    # Pass all plotting logic to a single AWK process
    awk -v width="$PLOT_WIDTH" -v height="$PLOT_HEIGHT" '
    # BEGIN block: Runs once before processing data. Set up constants and initial values.
    BEGIN {
        FS = ","
        temp_min = 9999
        temp_max = -9999
        hum_min = 0    # Fixed humidity range
        hum_max = 100
        hum_range = 100
    }

    # Main block: Runs for EVERY line of data. This is our "map" operation.
    # We read data into AWK arrays and find the temperature range on the fly.
    {
        timestamps[NR] = $1
        temperatures[NR] = $2
        humidities[NR] = $3
        if ($2 < temp_min) temp_min = $2
        if ($2 > temp_max) temp_max = $2
    }

    # END block: Runs once after all data has been read.
    # Here we build and print the entire plot.
    END {
        if (NR == 0) {
            print "No valid data points found"
            exit
        }

        # --- 1. Finalize ranges and initialize the plot grid ---
        temp_range = temp_max - temp_min
        if (temp_range < 1) temp_range = 1  # Avoid division by zero
        
        for (y = 0; y < height; y++) {
            for (x = 0; x < width; x++) {
                plot_grid[x, y] = " "
            }
        }

        # --- 2. Populate the grid by "mapping" data points to coordinates ---
        for (i = 1; i <= NR; i++) {
            x = int((i - 1) * (width - 1) / (NR - 1))
            if (NR == 1) x = int(width / 2); # Center a single point

            y_temp = int((temperatures[i] - temp_min) * (height - 1) / temp_range)
            y_hum = int((humidities[i] - hum_min) * (height - 1) / hum_range)

            # Place characters, handling overlaps
            if (y_temp >= 0 && y_temp < height) {
                if (plot_grid[x, y_temp] == " ") plot_grid[x, y_temp] = "▲" # Temperature
            }
            if (y_hum >= 0 && y_hum < height) {
                if (plot_grid[x, y_hum] == " ") plot_grid[x, y_hum] = "●" # Humidity
                else if (plot_grid[x, y_hum] == "▲") plot_grid[x, y_hum] = "◆" # Overlap
            }
        }

        # --- 3. Print the header, plot grid, and axes ---
        printf "Temperature: %.1f°C - %.1f°C | Humidity: %d%% - %d%%\n\n", temp_min, temp_max, hum_min, hum_max
        
        for (y = height - 1; y >= 0; y--) {
            y_val_temp = temp_min + (temp_range * y / (height - 1))
            y_val_hum = hum_min + (hum_range * y / (height - 1))
            printf "%5.1f°C %3.0f%% |", y_val_temp, y_val_hum

            for (x = 0; x < width; x++) {
                printf "%s", plot_grid[x, y]
            }
            print ""
        }

        # Draw X-axis
        printf "%14s+", ""
        for (x=0; x<width; x++) printf "-";
        print ""
    }
    ' "$data_file" # AWK reads the data file here

    # Print time labels and legend from Bash (simpler this way)
    printf "%15s" ""
    printf "%s%*s\n" "${start_time:11:5}" "$((PLOT_WIDTH - 5))" "${end_time:11:5}"
    echo
    echo "Legend: ▲ Temperature  ● Humidity  ◆ Both overlap"
    echo "Next refresh in $REFRESH_INTERVAL seconds..."
}


# Main monitoring loop
main() {
    tput civis  # Hide cursor
    
    while true; do
        local data_file=$(extract_recent_data)
        
        clear
        echo "Live Temperature & Humidity Monitor - Press Ctrl+C to exit"
        echo "==========================================================="
        printf "Last Update: %s | Data Points: %d\n" "$(date '+%H:%M:%S')" "$(wc -l < "$data_file")"
        
        draw_timeseries_plot "$data_file"
        
        rm -f "$data_file"
        sleep "$REFRESH_INTERVAL"
    done
}

# Start monitoring
echo "Starting live monitoring of $CSV_FILE"
echo "Configuration: Width=$PLOT_WIDTH, Height=$PLOT_HEIGHT, Points=$DATA_POINTS"
echo "Refresh interval: $REFRESH_INTERVAL seconds"
echo ""
echo "Press any key to start..."
read -n 1 -s

main
