**Copy and paste this to install**
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

Linux users always say how package management is so much easier compared to hunting down .exe files but there are so many package formats that it becomes even harder than on Windows. I merged all verified snaps and flatpaks together, or at least tried to and also added install options for a few apps that aren't a flatpak/snap.

As the name suggests, you just tell it to fetch something and it does it. No flags, no nothing.

`appfetch app1 app1 app3 app4`, who gives a fuck what format are the apps in, I just want them from the official source.

![image](https://github.com/user-attachments/assets/8f275fb6-591e-4f5b-abd7-241bbcb3f726)

![image](https://github.com/user-attachments/assets/96df4dbe-ecb5-4e55-b54d-ffb96782e8bf)

![image](https://github.com/user-attachments/assets/0a6da772-de30-46fa-b6a8-0ae3a446fe8a)

**I'm only testing this on Ubuntu and it will work on Debian too if it has snap installed.**
