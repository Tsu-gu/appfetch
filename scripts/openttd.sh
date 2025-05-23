#!/bin/bash

page_content=$(wget -qO- https://www.openttd.org/downloads/openttd-releases/latest)

version=$(echo "$page_content" | grep -oP 'Latest stable release in openttd is \K[0-9]+\.[0-9]+')

if [ -z "$version" ]; then
    echo "Failed to extract version number."
    exit 1
fi

echo "Downloading OpenTTD version $version..."
mkdir -p ~/Applications && \
wget "https://cdn.openttd.org/openttd-releases/${version}/openttd-${version}-linux-generic-amd64.tar.xz" -O /tmp/openttd.tar.xz && \
tar -xf /tmp/openttd.tar.xz -C ~/Applications
