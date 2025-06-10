#!/bin/bash

# Live Time Series ASCII Plotter for Temperature and Humidity
# Displays temperature and humidity on Y-axis, time on X-axis
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
    echo "Example: 2025-06-10 15:23:00,36.3,34.73"
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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--width)
            PLOT_WIDTH="$2"
            shift 2
            ;;
        -h|--height)
            PLOT_HEIGHT="$2"
            shift 2
            ;;
        -n|--points)
            DATA_POINTS="$2"
            shift 2
            ;;
        -r|--refresh)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$CSV_FILE" ]]; then
                CSV_FILE="$1"
            else
                echo "Error: Multiple files not supported"
                usage
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CSV_FILE" ]]; then
    echo "Error: No CSV file specified"
    usage
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "Error: File '$CSV_FILE' not found"
    exit 1
fi

# Function to extract and clean data
extract_recent_data() {
    local temp_file="/tmp/plot_data_$$"
    
    # Remove Windows line endings and extract recent data
    tail -n "$((DATA_POINTS + 10))" "$CSV_FILE" | \
    sed 's/\r$//' | \
    awk -F',' '
    BEGIN { OFS="," }
    {
        # Skip header
        if (NR == 1 && (tolower($1) ~ /timestamp/ || tolower($2) ~ /temperature/)) next
        
        # Clean fields
        gsub(/^[ \t]+|[ \t]+$/, "", $1)
        gsub(/^[ \t]+|[ \t]+$/, "", $2)
        gsub(/^[ \t]+|[ \t]+$/, "", $3)
        
        # Validate numeric fields
        if (NF >= 3 && $2 ~ /^-?[0-9]+\.?[0-9]*$/ && $3 ~ /^-?[0-9]+\.?[0-9]*$/) {
            print $1, $2, $3
        }
    }' | tail -n "$DATA_POINTS" > "$temp_file"
    
    echo "$temp_file"
}

# Function to draw time series plot
draw_timeseries_plot() {
    local data_file="$1"
    
    if [[ ! -s "$data_file" ]]; then
        echo "No data available"
        return
    fi
    
    # Read data into arrays
    local timestamps=()
    local temperatures=()
    local humidities=()
    
    while IFS=',' read -r ts temp hum; do
        timestamps+=("$ts")
        temperatures+=("$temp")
        humidities+=("$hum")
    done < "$data_file"
    
    local data_count=${#temperatures[@]}
    
    if [[ $data_count -eq 0 ]]; then
        echo "No valid data points found"
        return
    fi
    
    # Calculate ranges
    local temp_min=$(printf '%s\n' "${temperatures[@]}" | sort -n | head -1)
    local temp_max=$(printf '%s\n' "${temperatures[@]}" | sort -n | tail -1)
    
    # --- CHANGE 1: Set a fixed 0-100 range for humidity ---
    local hum_min=0
    local hum_max=100
    
    # Calculate range values
    local temp_range=$(awk "BEGIN {print $temp_max - $temp_min}")
    
    # --- CHANGE 2: Set humidity range to a fixed value ---
    local hum_range=100
    
    # Add padding to temperature range to avoid division by zero
    if (( $(awk "BEGIN {print ($temp_range < 1)}") )); then
        temp_range=1
        temp_max=$(awk "BEGIN {print $temp_min + 1}")
    fi
    
    # --- CHANGE 3: The old padding check for humidity is no longer needed ---
    
    # Clear screen and draw header
    clear
    echo "Live Temperature & Humidity Monitor - Press Ctrl+C to exit"
    echo "==========================================================="
    printf "Last Update: %s | Data Points: %d\n" "$(date '+%H:%M:%S')" "$data_count"
    # --- CHANGE 4: Update header to show the fixed humidity range ---
    printf "Temperature: %.1f°C - %.1f°C | Humidity: %d%% - %d%%\n" "$temp_min" "$temp_max" "$hum_min" "$hum_max"
    echo ""
    
    # Draw Y-axis labels and plot area
    for ((row = PLOT_HEIGHT - 1; row >= 0; row--)); do
        # Calculate Y-axis values
        local temp_val=$(awk "BEGIN {printf \"%.1f\", $temp_min + ($temp_range * $row / ($PLOT_HEIGHT - 1))}")
        # The logic here remains the same, but now uses the fixed hum_min and hum_range
        local hum_val=$(awk "BEGIN {printf \"%.0f\", $hum_min + ($hum_range * $row / ($PLOT_HEIGHT - 1))}")
        
        # Print Y-axis labels
        printf "%5.1f°C %3.0f%% |" "$temp_val" "$hum_val"
        
        # Plot data points
        # Using a simple loop for plotting. A more complex approach could handle scaling better.
        for ((i = 0; i < data_count; i++)); do
            # Calculate the plot column for the current data point
            local plot_col=$(( i * PLOT_WIDTH / data_count ))
            
            # This logic only prints a character if the current column matches the scaled position.
            # This is a simplified way to ensure one point per data entry on the x-axis.
            if [[ $plot_col -ne $(( (i-1) * PLOT_WIDTH / data_count )) ]] || [[ $i -eq 0 ]]; then
                local temp="${temperatures[$i]}"
                local hum="${humidities[$i]}"
                
                # Calculate positions. The humidity calculation now correctly scales to the 0-100 range.
                local temp_pos=$(awk "BEGIN {print int(($temp - $temp_min) * ($PLOT_HEIGHT - 1) / $temp_range)}")
                local hum_pos=$(awk "BEGIN {print int(($hum - $hum_min) * ($PLOT_HEIGHT - 1) / $hum_range)}")
                
                # Determine character to display
                local char=" "
                if [[ $temp_pos -eq $row ]] && [[ $hum_pos -eq $row ]]; then
                    char="◆"
                elif [[ $temp_pos -eq $row ]]; then
                    char="▲"
                elif [[ $hum_pos -eq $row ]]; then
                    char="●"
                fi
                printf "%s" "$char"
            fi
        done
        
        echo
    done
    
    # Draw X-axis
    printf "%14s+" ""
    printf "%${PLOT_WIDTH}s\n" "" | tr ' ' '-'
    
    # Draw time labels
    printf "%15s" ""
    local start_time="${timestamps[0]:11:5}"
    local end_time="${timestamps[-1]:11:5}"
    printf "%s%*s\n" "$start_time" "$((PLOT_WIDTH - 5))" "$end_time"
    
    echo
    echo "Legend: ▲ Temperature  ● Humidity  ◆ Both overlap"
    echo "Next refresh in $REFRESH_INTERVAL seconds..."
}


# Main monitoring loop
main() {
    tput civis  # Hide cursor
    
    while true; do
        # Extract recent data
        local data_file=$(extract_recent_data)
        
        # Draw the plot
        draw_timeseries_plot "$data_file"
        
        # Cleanup temporary file
        rm -f "$data_file"
        
        # Wait for next refresh
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
