#!/bin/bash

# Stop on first error
set -e

echo "🚀 Starting PostgresGUI build process..."

# Clean and build the project
# The generated files will be output to the local "./build" folder
xcodebuild -project PostgresGUI.xcodeproj \
           -scheme PostgresGUI \
           -configuration Release \
           -derivedDataPath build/ \
           -allowProvisioningUpdates \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGN_ENTITLEMENTS="" \
           CODE_SIGNING_ALLOWED=NO \
           clean build

# Define paths
APP_PATH="build/Build/Products/Release/PostgresGUI.app"

# Check if the build was successful and generated the .app
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App not found at $APP_PATH. The build may have failed."
    exit 1
fi

# Extract version from the built app's Info.plist
APP_VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
DMG_NAME="PostgresGUI-${APP_VERSION}.dmg"

echo "✅ Build completed successfully!"
echo "📦 Packaging into $DMG_NAME..."

# Remove previous DMG if it exists
if [ -f "$DMG_NAME" ]; then
    rm "$DMG_NAME"
fi

# Check if the user has create-dmg installed (creates nicer DMGs)
if command -v create-dmg &> /dev/null; then
    echo "✨ Using 'create-dmg'..."
    create-dmg \
      --volname "PostgresGUI" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "PostgresGUI.app" 150 190 \
      --hide-extension "PostgresGUI.app" \
      --app-drop-link 450 185 \
      "$DMG_NAME" \
      "$APP_PATH"
else
    echo "⚠️ 'create-dmg' not found. (Recommended: brew install create-dmg)"
    echo "⚙️ Using native macOS 'hdiutil' as fallback..."
    hdiutil create -volname "PostgresGUI" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_NAME"
fi

echo "🎉 Done! The file $DMG_NAME was successfully created."
