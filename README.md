# R_e 🎄

## 🗝️ Network_Login
```
bash -c "$(wget -qO-  https://github.com/1kaiser/R_e/releases/download/1/prepare_login.sh)"
```
or
```
bash -c "$(wget -qO-  https://raw.githubusercontent.com/1kaiser/R_e/main/prepare_login.sh)"
```

## 🧪 SHT4x_Trinkey 

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


## 📃 [tmux](https://github.com/tmux/tmux)
```
bash -c "sudo apt update && sudo apt install -y tmux && wget -O ~/.tmux.conf https://raw.githubusercontent.com/1kaiser/R_e/main/.tmux.conf && tmux"
```


## 📸 [Pi_Camera_Setup](https://www.raspberrypi.com/documentation/computers/camera_software.html)
```
bash -c "wget -O ~/SnapSetup.sh https://raw.githubusercontent.com/1kaiser/R_e/main/SnapSetup.sh && chmod +x ~/SnapSetup.sh && ~/SnapSetup.sh your_remote_user your_remote_host /path/to/destination 'your_password' yourusername/your-repo"
```
