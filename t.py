import os
import time
import csv
import serial
from multiprocessing import Process, Queue, Value

# Configuration
com_port = '/dev/ttyACM0'  # Adjust this to your COM port
baud_rate = 115200  # Adjust this to the baud rate of your sensor
base_csv_file_path = 'sensor_readings'  # Base path for the CSV file

def find_next_file_name(base_path):
    """Find the next available file name with a numeric suffix."""
    index = 0
    while True:
        file_path = f"{base_path}_{index}.csv"
        if not os.path.exists(file_path):
            return file_path
        index += 1

def read_sensor_data(ser):
    line = ser.readline().decode('utf-8').strip()
    # print(f"Received line: {line}")  # Debug output
    try:
        parts = line.split(',')
        if len(parts) >= 3:
            temperature = parts[1].strip()
            humidity = parts[2].strip()
            return float(temperature), float(humidity)
        else:
            print("Received data is not in the expected format.")
            return None, None
    except ValueError:
        print("Received data is not in the expected format.")
        return None, None

def save_to_csv(file_path, temperature, humidity):
    with open(file_path, mode='a', newline='') as file:
        writer = csv.writer(file)
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        writer.writerow([timestamp, temperature, humidity])
        # print(f"Saved to CSV: {timestamp}, {temperature}, {humidity}")

def data_logging(queue, com_port, baud_rate, base_csv_file_path, running_flag):
    try:
        csv_file_path = find_next_file_name(base_csv_file_path)
        
        # Write CSV header if the file does not exist or is empty
        if not os.path.exists(csv_file_path) or os.path.getsize(csv_file_path) == 0:
            with open(csv_file_path, mode='w', newline='') as file:
                writer = csv.writer(file)
                writer.writerow(["Timestamp", "Temperature", "Humidity"])
        
        with serial.Serial(com_port, baud_rate, timeout=1) as ser:
            print(f"Starting data logging to {csv_file_path}... Press Ctrl+C to stop.")
            running_flag.value = 1
            while True:
                temperature, humidity = read_sensor_data(ser)
                if temperature is not None and humidity is not None:
                    # print(f"Temperature: {temperature} °C, Humidity: {humidity} %")
                    save_to_csv(csv_file_path, temperature, humidity)
                time.sleep(1)
    except Exception as e:
        print(f"Data logging encountered an error: {e}")
        running_flag.value = 0

def monitor_processes(data_logging_flag, queue):
    while True:
        if data_logging_flag.value == 0:
            print("Restarting data logging process...")
            data_logging_process = Process(target=data_logging, args=(queue, com_port, baud_rate, base_csv_file_path, data_logging_flag))
            data_logging_process.start()
            data_logging_process.join()  # Ensure the new process is joined
        time.sleep(5)

def main():
    queue = Queue()
    data_logging_flag = Value('i', 1)

    data_logging_process = Process(target=data_logging, args=(queue, com_port, baud_rate, base_csv_file_path, data_logging_flag))
    monitor_process = Process(target=monitor_processes, args=(data_logging_flag, queue))

    data_logging_process.start()
    monitor_process.start()

    data_logging_process.join()
    monitor_process.join()

if __name__ == "__main__":
    main()
