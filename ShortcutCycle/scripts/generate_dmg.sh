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

# Prepare for DMG
echo "Preparing app for DMG..."
mkdir -p "$EXPORT_PATH"
cp -r "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_PATH/"

# Create DMG using hdiutil
echo "Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$EXPORT_PATH" -ov -format UDZO "$DMG_NAME"

if [ $? -ne 0 ]; then
    echo "DMG creation failed"
    exit 1
fi

echo "----------------------------------------"
echo "Build Successful!"
echo "DMG Location: $(pwd)/$DMG_NAME"
echo "----------------------------------------"
