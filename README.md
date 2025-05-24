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
appfetch update-database
```
I encountered issues with the script trying to update itself so I guess if you want to update it, re-run the installation command.

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
![image](https://github.com/user-attachments/assets/8f275fb6-591e-4f5b-abd7-241bbcb3f726)

![image](https://github.com/user-attachments/assets/96df4dbe-ecb5-4e55-b54d-ffb96782e8bf)

![image](https://github.com/user-attachments/assets/0a6da772-de30-46fa-b6a8-0ae3a446fe8a)
![image](https://github.com/user-attachments/assets/117bd294-2f96-4808-9826-e9a3293d8ef8)


**I'm only testing this on Ubuntu and it will work on Debian too if it has snap installed.**

# Exceptions to "official packages only": 
- mpv
- xfburn
- audacious
- makemkv
- yacreader (unverified but the flatpak is linked as official on their site)
- wireshark

I think it's better to break my own rules than just throw an error when a user wants to install one of these.
