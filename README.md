![appfetch-logo](https://github.com/user-attachments/assets/b607848d-1478-4d2b-9fb7-4d17c05377e2)


**Installation**
```
mkdir -p "$HOME/Documents" && \
wget -O "/tmp/apps.yaml" https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/apps.yaml && \
wget -O "/tmp/appfetch" https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/appfetch.sh && \
mv /tmp/apps.yaml "$HOME/Documents/apps.yaml" && \
sudo mv /tmp/appfetch /usr/local/bin/appfetch && \
sudo chmod +x /usr/local/bin/appfetch
```

**To update its database:**

```
appfetch update
```
I encountered issues with the script trying to update itself so if you want to update it, re-run the installation command.

**Search for apps with:**

```
appfetch search app1 app2 app3...
```

**Install apps with:**

```
appfetch app1 app2 app3...
```
Yes. There is no install command because it's just wasted time. You want apps, you run the command and tell it what you want.

**To avoid snaps when possible:**

Find the variable `PREFER_SNAP` inside of the script and set it to false

**To report bugs/missing apps:**

```
appfetch bug
```

# Showcase
![image](https://github.com/user-attachments/assets/047cef5c-be13-426f-947e-6ca074db8b88)
![image](https://github.com/user-attachments/assets/9ee4d99f-6ecb-401c-ae98-4641d78f9b83)
![image](https://github.com/user-attachments/assets/119c8bef-773d-4899-a0f9-033b76d39222)
![image](https://github.com/user-attachments/assets/43a20d4c-8ffb-47a1-8ad7-7a3c115f3e70)


**I'm only testing this on Ubuntu and it will work on Debian too if it has snap installed.**

If some AppImages aren't launching, install `libfuse2t64` via your package manager. A lot of them still rely on the outdated FUSE library.

# Exceptions to "official packages only": 
- mpv
- xfburn
- audacious
- makemkv
- yacreader (unverified but the flatpak is linked as official on their site)
- wireshark

I think it's better to break my own rules than just throw an error when a user wants to install one of these.
