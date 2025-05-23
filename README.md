**Installation**
```
cd $HOME/Documents
wget https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/apps.yaml 
cd $HOME
wget https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/appfetch.sh
sudo cp $HOME/appfetch.sh /usr/local/bin/appfetch
sudo rm $HOME/appfetch.sh 
```

**To update it and its database:**

```
appfetch update
```
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
