#!/bin/bash

# Fetch the page content
page_content=$(wget -qO- https://www.wps.com/whatsnew/linux/)

# Extract the version from the embedded JS and strip newline
version=$(echo "$page_content" | grep -oP 'WPS Office 2019 for Linux \(\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr -d '\n')

# Check for extraction success
if [ -z "$version" ]; then
    echo "Failed to extract version number."
    exit 1
fi

# Extract the build number (last segment) and strip newline
build_number=$(echo "$version" | awk -F. '{print $4}' | tr -d '\n')

# Construct filename and URL
filename="wps-office_${version}.XA_amd64.deb"
url="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/${build_number}/${filename}"

# Spoof User-Agent to bypass 403
user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

# Download with spoofed User-Agent
echo "Downloading $filename from $url..."
wget --header="User-Agent: $user_agent" -O "$filename" "$url"

# Confirm success
if [ $? -eq 0 ]; then
    echo "Download complete: $filename"
else
    echo "Download failed."
    exit 1
fi

# Fuck their website, this will never work
