![appfetch-logo](https://github.com/user-attachments/assets/b607848d-1478-4d2b-9fb7-4d17c05377e2)

- [Installation and usage](#installation)
  - [To update its database](#to-update-its-database)
  - [Search for apps with](#search-for-apps-with)
  - [Install apps with](#install-apps-with)
  - [To avoid snaps when possible](#to-avoid-snaps-when-possible)
  - [To report bugs/missing apps](#to-report-bugsmissing-apps)
- [Showcase](#showcase)
- [What happens when a package is not found in the database?](#what-happens-when-a-package-is-not-found-in-the-database)
- [Contributing](#contributing)
  - [Example 1](#example-of-an-app-with-no-official-flatpak-or-snap-available)
  - [Example 2](#example-of-an-app-with-official-flatpak-or-snap-available)


The point of this tool is to allow you to install software from its official source on Linux. It achieves that by searching a database I put together which contains official snaps and flatpaks, as well as many apps I added manually which can only be installed by going to their websites. 

An exception to this are unverified snaps and flatpaks that are linked on the project's websites and promoted as the official installation methods (such as YACreader or qtox)

**I'm only testing this on Ubuntu and targetting the install scripts for it. But most apps comes in a distro-agnostic format so you can use this elsewhere if you don't mind a few failed commands.**

If some AppImages aren't launching, install `libfuse2t64` via your package manager. A lot of them still rely on the outdated FUSE library.

# Installation
```
wget -O "/tmp/apps.yaml" https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/apps.yaml && \
wget -O "/tmp/appfetch" https://raw.githubusercontent.com/Tsu-gu/appfetch/refs/heads/main/appfetch.sh && \
mv /tmp/apps.yaml "$HOME/Documents/apps.yaml" && \
sudo mv /tmp/appfetch /usr/local/bin/appfetch && \
sudo chmod +x /usr/local/bin/appfetch
```

I encountered issues with the script trying to update itself so if you want to update it, re-run the installation command.

## To update its database:

```
appfetch update
```

## Search for apps with:

```
appfetch search app1 app2 app3...
```

## Install apps with:

```
appfetch app1 app2 app3...
```
Yes. There is no install command because it's just wasted time. You want apps, you run the command and tell it what you want.

## To avoid snaps when possible:

Find the variable `PREFER_SNAP` inside of the script and set it to false

## To report bugs/missing apps:

```
appfetch bug
```

# Showcase
![image](https://github.com/user-attachments/assets/047cef5c-be13-426f-947e-6ca074db8b88)
![image](https://github.com/user-attachments/assets/9ee4d99f-6ecb-401c-ae98-4641d78f9b83)
![image](https://github.com/user-attachments/assets/119c8bef-773d-4899-a0f9-033b76d39222)
![image](https://github.com/user-attachments/assets/43a20d4c-8ffb-47a1-8ad7-7a3c115f3e70)


# What happens when a package is not found in the database?

A tool called [mpm](https://github.com/kdeldycke/meta-package-manager) is used. It launches the search command for all package managers on your system and outputs a list.

![mpm](https://github.com/user-attachments/assets/f786d817-ea89-4171-8fee-9716469b7f77)

# Contributing

Just make a PR with an entry like what you see in apps.yaml. Be careful about trailing whitespaces.

## Example of an app with no official flatpak or snap available:
```
yt-dlp:
  custom: mkdir -p ~/Applications && cd ~/Applications && wget LINK/yt-dlp && chmod +x yt-dlp
  uninstall: rm -rf $HOME/Applications/yt-dlp
  aliases: [ytdlp, yt]
  comment: Youtube video downloading tool
```
## Example of an app with official flatpak or snap available:
```
brave:
  snap: brave
  flatpak: com.brave.Browser
  aliases: [brave-browser]
  comment: A chrome fork with an adblock and crypto
```

If only one of them exists, you don't put in the other one
