#!/bin/bash

page_content=$(wget -qO- https://www.audacityteam.org/download/linux/)

version=$(echo "$page_content" | grep -oP 'Current version \K[0-9]+\.[0-9]+\.[0-9]+')

if [ -z "$version" ]; then
    echo "Failed to extract version number."
    exit 1
fi

echo "Downloading Audacity version $version..."
mkdir -p ~/Applications
cd  ~/Applications
wget https://github.com/audacity/audacity/releases/download/Audacity-${version}/audacity-linux-${version}-x64-22.04.AppImage 
chmod +x audacity-linux-${version}-x64-22.04.AppImage 
