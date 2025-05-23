#!/bin/bash

# Fetch the page content
page_content=$(wget -qO- https://www.wps.com/whatsnew/linux/)

# Extract the version number from the page content
# The pattern is like 11.1.0.11723 or similar, so look for 4 numbers separated by dots
version=$(echo "$page_content" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ -z "$version" ]; then
    echo "Failed to extract version number."
    exit 1
fi

# Extract build number (last part)
build_number=$(echo "$version" | awk -F. '{print $4}')

# Compose filename and url
filename="wps-office_${version}.XA_amd64.deb"
url="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/${build_number}/${filename}"

# Spoof User-Agent
user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

echo "Downloading $filename from $url..."
cd ~/Downloads
wget --header="User-Agent: $user_agent" -O "$filename" "$url"

sudo apt install -y ~/Downloads/wps-*.deb

if [ $? -eq 0 ]; then
    echo "Download complete: $filename"
else
    echo "Download failed."
    exit 1
fi
