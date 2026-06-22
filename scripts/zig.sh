#!/bin/bash
set -e

cd "$(dirname "$0")/.."

ZIG_VERSION="0.15.2"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then 
    ARCH="x86_64"
elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then 
    ARCH="aarch64"
else 
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

if [ "$OS" = "darwin" ]; then 
    OS="macos"
fi

DIR_NAME="zig-$ARCH-$OS-$ZIG_VERSION"
TAR_NAME="$DIR_NAME.tar.xz"
URL="https://ziglang.org/download/$ZIG_VERSION/$TAR_NAME"

echo "Downloading Zig $ZIG_VERSION for $OS-$ARCH..."
wget "$URL"

echo "Extracting..."
tar -xf "$TAR_NAME"
rm "$TAR_NAME"

ln -sf "$DIR_NAME/zig" local_zig

echo "================================================="
echo "✅ Local Zig $ZIG_VERSION setup complete!"
echo "================================================="
