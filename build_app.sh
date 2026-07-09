#!/bin/bash
set -e

echo "Building LimitBank in Release mode..."
swift build -c release

echo "Creating LimitBank.app structure..."
rm -rf LimitBank.app
mkdir -p LimitBank.app/Contents/MacOS
mkdir -p LimitBank.app/Contents/Resources

echo "Copying binary..."
cp .build/release/LimitBank LimitBank.app/Contents/MacOS/LimitBank

if [ -f "AppIcon.icns" ]; then
    echo "Copying app icon..."
    cp AppIcon.icns LimitBank.app/Contents/Resources/AppIcon.icns
fi

if [ -f "secrets.json" ]; then
    echo "Copying secrets config..."
    cp secrets.json LimitBank.app/Contents/Resources/secrets.json
fi

echo "Writing Info.plist..."
cat << 'EOF' > LimitBank.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LimitBank</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.dendyelo.LimitBank</string>
    <key>CFBundleName</key>
    <string>LimitBank</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "LimitBank.app built successfully!"
