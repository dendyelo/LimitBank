#!/bin/bash
set -e

SOURCE_IMG="$1"
if [ -z "$SOURCE_IMG" ]; then
    echo "Usage: ./generate_icns.sh <path_to_image>"
    exit 1
fi

echo "Creating AppIcon.iconset..."
ICONSET_DIR="AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Generate the various sizes using sips
sips -s format png -z 16 16     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$SOURCE_IMG" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$SOURCE_IMG" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$SOURCE_IMG" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

echo "Compiling to AppIcon.icns using iconutil..."
iconutil -c icns "$ICONSET_DIR"

echo "Cleaning up..."
rm -rf "$ICONSET_DIR"

echo "AppIcon.icns created successfully!"
