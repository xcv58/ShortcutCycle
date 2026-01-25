#!/bin/bash

# Configuration
APP_NAME="ShortcutCycle"
SCHEME="ShortcutCycle"
PROJECT="ShortcutCycle.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
DMG_NAME="$APP_NAME.dmg"

# Ensure we are in the project root
if [ ! -d "$PROJECT" ]; then
    echo "Error: Please run this script from the project root containing $PROJECT"
    exit 1
fi

# Clean
echo "Cleaning build directory..."
rm -rf "$BUILD_DIR"
rm -f "$DMG_NAME"

# Archive
echo "Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  -quiet

if [ $? -ne 0 ]; then
    echo "Archive failed"
    exit 1
fi

# Create DMG using create-dmg tool
echo "Creating DMG using create-dmg..."

if [ ! -d "scripts/create-dmg-tool" ]; then
    echo "Error: create-dmg tool not found in scripts/create-dmg-tool"
    exit 1
fi

./scripts/create-dmg-tool/create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 650 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 120 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 475 120 \
  --background "scripts/dmg_background.png" \
  "$DMG_NAME" \
  "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

if [ $? -ne 0 ]; then
    echo "DMG creation failed"
    exit 1
fi

echo "----------------------------------------"
echo "Build Successful!"
echo "DMG Location: $(pwd)/$DMG_NAME"
echo "----------------------------------------"
