#!/bin/bash

# UV Environment Temperature & Humidity Sensor Reader
# Usage: ./sensor_reader.sh [COM_PORT] [BAUD_RATE]
# Remote: curl -sL https://raw.githubusercontent.com/USER/REPO/main/sensor_reader.sh | bash -s [COM_PORT] [BAUD_RATE]
# Example: curl -sL https://raw.githubusercontent.com/USER/REPO/main/sensor_reader.sh | bash -s /dev/ttyACM0 115200

set -e

# Configuration
COM_PORT="${1:-/dev/ttyACM0}"
BAUD_RATE="${2:-115200}"
ENV_NAME="sensor_env_$(date +%s)"

echo "🌡️  UV Sensor Reader (Remote Ready)"
echo "📍 COM Port: $COM_PORT"
echo "⚡ Baud Rate: $BAUD_RATE"
echo "🌐 Script: github.com/USERNAME/REPO/main/sensor_reader.sh"
echo ""

# Check if device exists
if [ ! -e "$COM_PORT" ]; then
    echo "❌ Error: Device $COM_PORT does not exist"
    echo "💡 Available serial devices:"
    ls /dev/tty* 2>/dev/null | grep -E '(ACM|USB)' | head -10 || echo "   No USB/ACM devices found"
    echo "💡 Try: ls /dev/tty* | grep -E '(ACM|USB)'"
    exit 1
fi

# Check if UV is installed
if ! command -v uv >/dev/null 2>&1; then
    echo "❌ UV not found. Installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Ensure UV is in PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
    
    # Verify installation
    if ! command -v uv >/dev/null 2>&1; then
        echo "❌ UV installation failed"
        exit 1
    fi
    echo "✅ UV installed!"
fi

echo "🚀 Creating UV environment: $ENV_NAME"
uv venv $ENV_NAME --quiet

echo "📦 Installing pyserial..."
uv pip install --python $ENV_NAME pyserial --quiet

echo "✅ Environment ready! Press Ctrl+C to stop"
echo "=================================================="

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up UV environment: $ENV_NAME"
    rm -rf $ENV_NAME
    echo "✅ Environment destroyed!"
    exit 0
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Export variables for Python script
export COM_PORT="$COM_PORT"
export BAUD_RATE="$BAUD_RATE"

# Create and run Python script with UV
cat << 'EOF' | uv run --python $ENV_NAME python3 -
import serial
import time
import sys
import os

# Get configuration from environment variables
com_port = os.environ.get('COM_PORT', '/dev/ttyACM0')
baud_rate = int(os.environ.get('BAUD_RATE', '115200'))

def read_sensor_data(ser):
    """Read and parse sensor data from serial port"""
    try:
        line = ser.readline().decode('utf-8').strip()
        if line:
            parts = line.split(',')
            if len(parts) >= 4:
                # Full sensor data: ID, Temp, Humidity, Extra
                sensor_id = parts[0].strip()
                temp = float(parts[1].strip())
                hum = float(parts[2].strip())
                extra = float(parts[3].strip())
                return temp, hum, extra, sensor_id
            elif len(parts) >= 3:
                temp = float(parts[1].strip())
                hum = float(parts[2].strip())
                return temp, hum, None, None
            elif len(parts) == 2:
                temp = float(parts[0].strip())
                hum = float(parts[1].strip())
                return temp, hum, None, None
    except Exception:
        pass  # Silently skip malformed data
    return None, None, None, None

def test_connection(ser):
    """Test if we can read any data from the device"""
    print("🔍 Testing connection...")
    start = time.time()
    while time.time() - start < 5:
        try:
            if ser.in_waiting > 0:
                data = ser.readline().decode('utf-8', errors='ignore').strip()
                if data:
                    print("✅ Connection confirmed!")
                    return True
        except:
            pass
        time.sleep(0.1)
    print("❌ No data received")
    return False

def main():
    try:
        print(f"🔌 Connecting to {com_port}...")
        
        # Open serial connection
        with serial.Serial(
            port=com_port, 
            baudrate=baud_rate, 
            timeout=2,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            bytesize=serial.EIGHTBITS
        ) as ser:
            
            print("✅ Connected!")
            time.sleep(2)  # Device initialization time
            ser.flushInput()  # Clear buffer
            
            # Test connection
            if not test_connection(ser):
                print("💡 Troubleshooting:")
                print("   - Try different baud rates: 9600, 57600, 115200")
                print("   - Check device power and connections")
                return
            
            print("📊 Live readings:")
            print("-" * 50)
            
            reading_count = 0
            consecutive_failures = 0
            
            while True:
                temp, hum, extra, sensor_id = read_sensor_data(ser)
                if temp is not None and hum is not None:
                    reading_count += 1
                    consecutive_failures = 0
                    timestamp = time.strftime("%H:%M:%S")
                    
                    if extra is not None:
                        print(f"[{timestamp}] #{reading_count:03d} | {temp:6.2f}°C | {hum:6.2f}% | Conductivity: {extra:6.0f}")
                    else:
                        print(f"[{timestamp}] #{reading_count:03d} | {temp:6.2f}°C | {hum:6.2f}%")
                else:
                    consecutive_failures += 1
                    if consecutive_failures > 10:
                        print("⚠️  Multiple parsing failures - check data format")
                        consecutive_failures = 0  # Reset counter
                
                time.sleep(0.5)  # Read every 0.5 seconds
                
    except serial.SerialException as e:
        print(f"❌ Serial error: {e}")
        print("💡 Try: sudo chmod 666 " + com_port)
    except PermissionError:
        print(f"❌ Permission denied accessing {com_port}")
        print(f"💡 Run: sudo chmod 666 {com_port}")
    except KeyboardInterrupt:
        print(f"\n📊 Total readings captured: {reading_count}")
        print("👋 Goodbye!")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

if __name__ == "__main__":
    main()
EOF
