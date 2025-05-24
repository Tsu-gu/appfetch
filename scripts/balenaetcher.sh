mkdir -p ~/Applications && cd ~/Applications && \
VERSION=$(curl -s https://github.com/balena-io/etcher/releases | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//' | sort -Vr | head -n 1) && \
wget https://github.com/balena-io/etcher/releases/download/v$VERSION/balenaEtcher-linux-x64-$VERSION.zip && \
unzip balenaEtcher-linux-x64-$VERSION.zip && \
rm -f balenaEtcher-linux-x64-$VERSION.zip
