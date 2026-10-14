#!/bin/bash
set -e

APP_NAME="Audio Splitter"
BUILD_APP_PATH="build/macos/Build/Products/Release/$APP_NAME.app"
OUTPUT_DMG="Audio_Splitter_Installer.dmg"
TEMP_DIR="dmg_temp_packaging"

echo "=========================================="
echo " Packaging $APP_NAME into DMG Installer"
echo "=========================================="

if [ "$1" == "--build" ] || [ ! -d "$BUILD_APP_PATH" ]; then
    echo "📦 Building macOS Release application..."
    if command -v fvm &> /dev/null; then
        fvm flutter build macos --release
    else
        flutter build macos --release
    fi
fi

if [ ! -d "$BUILD_APP_PATH" ]; then
    echo "❌ Error: $BUILD_APP_PATH not found!"
    exit 1
fi

echo "📂 Preparing package folder..."
rm -rf "$TEMP_DIR" "$OUTPUT_DMG"
mkdir -p "$TEMP_DIR"

echo "📋 Copying application..."
cp -R "$BUILD_APP_PATH" "$TEMP_DIR/"

echo "🔗 Creating /Applications link..."
ln -s /Applications "$TEMP_DIR/Applications"

echo "💿 Creating disk image ($OUTPUT_DMG)..."
hdiutil create -volname "$APP_NAME" -srcfolder "$TEMP_DIR" -ov -format UDZO "$OUTPUT_DMG"

echo "🧹 Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "=========================================="
echo "✅ DMG Installer created successfully!"
echo "📍 Location: $(pwd)/$OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
echo "=========================================="
