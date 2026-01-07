# R_e 🎄

## 🗝️ Network_Login
Graphical 🌪️ running
```
wget https://raw.githubusercontent.com/1kaiser/R_e/main/prepare_login.sh && chmod +x prepare_login.sh && ./prepare_login.sh local_ip username 'password' login_id login_password
```
Flash ☄️ execution/running
```
bash -c "$(wget https://raw.githubusercontent.com/1kaiser/R_e/main/prepare_login.sh && chmod +x prepare_login.sh && ./prepare_login.sh local_ip username 'password' login_id login_password)"
```
## 🌡️📹 temperature imager setup
```
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/1kaiser/R_e/main/temp_cam.sh)" _ image /dev/video2 
```
## 🧪 SHT4x_Trinkey 
<details>
<summary><b>📱 How to run on Android (Termux) - No Root Required</b></summary>
<br>

To run the Adafruit SHT41 Trinkey temperature and humidity monitor on an Android phone using Termux, you need to overcome a specific Android limitation: **Termux cannot directly access USB devices** (like `/dev/ttyACM0`) on non-rooted phones due to security permissions.

To get around this, you should use a dedicated Android app to handle the USB connection and log the data to a file, which Termux can then read, format, and visualize in real-time.

Here is the step-by-step solution:

### Step 1: Prepare the Trinkey
Ensure your SHT41 Trinkey is running its default code (or CircuitPython) which outputs data in CSV format.
*   **Default Output Format:** `SerialNumber, Temperature, Humidity, TouchValue`
*   *Note: The Trinkey does not have a real-time clock, so it sends data without a timestamp. We will add the timestamp on the phone.*

### Step 2: Install the "Driver" App
Since Termux cannot open the USB port directly, use the highly reliable **Serial USB Terminal** app to act as the bridge.
1.  Install **[Serial USB Terminal](https://play.google.com/store/apps/details?id=de.kai_morich.serial_usb_terminal)** (by Kai Morich) from the Google Play Store.
2.  Connect your Trinkey to the phone using a **USB OTG adapter**.
3.  Open the app. It should detect the device (likely as a CDC/ACM device).
4.  Tap the **Connect** button (plug icon) to ensure data is streaming. You should see lines of text appearing (e.g., `123456, 24.50, 48.10, 800`).

### Step 3: Configure Logging
Configure the app to save this data to a file that Termux can access.
1.  In the app, go to **Settings** (hamburger menu) > **Data**.
    *   **Show timestamp:** Set to `yyyy-MM-dd HH:mm:ss.SSS`.
2.  Go to **Settings** > **Logging**.
    *   **Log to file:** Enable it.
    *   **Log directory:** Choose a shared folder, e.g., `Downloads`.
    *   **File name:** Set it to `trinkey_raw.txt`.
    *   **Log existing data:** Check this if you want to keep history, or leave unchecked to start fresh.
3.  Return to the main terminal screen. Ensure the **Log** switch (usually a green toggle or icon) is enabled.

### Step 4: Setup Termux
Open Termux and grant it access to your storage so it can read the log file.
```bash
termux-setup-storage
```
*(Accept the Android permission popup)*

Install the necessary tools (if you haven't already):
```bash
pkg install coreutils awk grep
```

### Step 5: Create the "Bridge" Script
The "Serial USB Terminal" app creates a log file that looks roughly like this:
`2023-10-27 10:00:01.123: 123456, 24.50, 48.10, 800`

However, your visualization script (`TemHumLive.sh`) expects:
`timestamp,temperature,humidity`

You need a background command to convert the format in real-time. Run this command in Termux:

```bash
# This continuously reads the raw log, extracts the time, temp, and humidity, 
# and saves it to a clean CSV file.
# Adjust the column numbers ($4, $5) below if your Trinkey output order is different.

tail -F /sdcard/Download/trinkey_raw.txt | \
grep --line-buffered "," | \
awk -F '[,: ]+' '{OFS=","; print $1" "$2, $5, $6}' > ~/stream_data.csv &
```
*   **Explanation:**
    *   `tail -F`: Follows the file as it grows.
    *   `awk`: Parses the messy log line. It grabs the Date+Time ($1+$2) and the Temperature ($5) and Humidity ($6) columns (skipping the Serial Number).
    *   `>`: Writes to `stream_data.csv` inside Termux's home folder.
    *   `&`: Runs this process in the background.

### Step 6: Run the Visualization
Now you can run the script you provided, pointing it at the clean data file.

1.  Download the script (if you haven't already):
    ```bash
    wget https://raw.githubusercontent.com/1kaiser/R_e/refs/heads/main/TemHumLive.sh
    chmod +x TemHumLive.sh
    ```

2.  Run it:
    ```bash
    ./TemHumLive.sh ~/stream_data.csv
    ```

### Summary of Workflow
1.  **Plug in Trinkey** via OTG.
2.  Open **Serial USB Terminal**, Connect, and ensure **Logging** is ON.
3.  Open **Termux**.
4.  Run the **awk** command (Step 5) to start converting data in the background.
5.  Run `./TemHumLive.sh ~/stream_data.csv`.

**Troubleshooting Tips:**
*   **Columns are wrong?** If the plot shows weird values, check the raw log format: `cat /sdcard/Download/trinkey_raw.txt`. Count the fields (separated by spaces, commas, or colons) and adjust the `$5, $6` in the `awk` command in Step 5 accordingly.
*   **Permission Denied?** Ensure you ran `termux-setup-storage` and accepted the permissions.
*   **No Data?** Ensure the Serial USB Terminal app is actually connected (plug icon is closed/green) and the "Log" feature is active.

</details>

```
bash -c "$(wget -qO- https://raw.githubusercontent.com/1kaiser/R_e/main/sensor_live.sh)" sensor_reader /dev/ttyACM0 115200
```

```
bash -c "wget -O ~/t_setup.sh https://raw.githubusercontent.com/1kaiser/R_e/main/t_setup.sh && chmod +x ~/t_setup.sh && ~/t_setup.sh"
```
`crontab -e`

```
# Run script every 5 minutes
*/5 * * * * ~/t_setup.sh

# Run script after reboot
@reboot ~/t_setup.sh
```

`bash -c "wget -O t.py https://raw.githubusercontent.com/1kaiser/R_e/main/t.py && python t.py"`


```
python <<EOF
import serial, time

with serial.Serial('/dev/ttyACM0', 115200, timeout=1) as ser:
    print("Reading raw sensor data. Press Ctrl+C to exit.")
    try:
        while True:
            line = ser.readline().decode(errors='replace').strip()
            if line:
                print(time.strftime("%Y%m%d%H%M%S"), line)
    except KeyboardInterrupt:
        print("Exiting...")
EOF
```

## 📃 [tmux](https://github.com/tmux/tmux)
```
bash -c "sudo apt update && sudo apt install -y tmux && wget -O ~/.tmux.conf https://raw.githubusercontent.com/1kaiser/R_e/main/.tmux.conf && tmux"
```


## 📸 [Pi_Camera_Setup](https://www.raspberrypi.com/documentation/computers/camera_software.html)
```
bash -c "wget -O ~/SnapSetup.sh https://raw.githubusercontent.com/1kaiser/R_e/main/SnapSetup.sh && chmod +x ~/SnapSetup.sh && ~/SnapSetup.sh your_remote_user your_remote_host /path/to/destination 'your_password' yourusername/your-repo"
```


## ☀️🛰️ [GOES_X_Setup](https://www.swpc.noaa.gov/products/goes-x-ray-flux)
```
bash -c "wget -O ~/GOES_X_setup.sh https://raw.githubusercontent.com/1kaiser/R_e/main/GOES_X_setup.sh && chmod +x ~/GOES_X_setup.sh && ~/GOES_X_setup.sh /path/to/folder"
```

## ✨🖥️ spack 

```
bash -c "wget -O ~/setup_spack.sh https://raw.githubusercontent.com/1kaiser/R_e/main/setup_spack.sh && chmod +x ~/setup_spack.sh && ~/setup_spack.sh {myproject} {4} {~/spack} {~/new_install}"
```

## 🪩 x13 flow

```
sudo taskset -c 0,1 dpkg --configure linux-image-amd64 
```
