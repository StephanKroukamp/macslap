#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="MacSlap"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="MacSlap.dmg"
DMG_PATH="$HOME/Desktop/$DMG_NAME"

echo "=== Building $APP_NAME ==="

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/MacSlap/Info.plist" "$APP_BUNDLE/Contents/"

# Copy sounds
cp "$PROJECT_DIR/MacSlap/Sounds/"*.aiff "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# Copy icon
cp "$PROJECT_DIR/MacSlap/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# Find the macOS SDK
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
echo "Using SDK: $SDK_PATH"

# Compile Swift source files
echo "Compiling..."
SWIFT_FILES=(
    "$PROJECT_DIR/MacSlap/MacSlapApp.swift"
    "$PROJECT_DIR/MacSlap/AppState.swift"
    "$PROJECT_DIR/MacSlap/SlapDetector.swift"
    "$PROJECT_DIR/MacSlap/LidAngleMonitor.swift"
    "$PROJECT_DIR/MacSlap/SoundManager.swift"
    "$PROJECT_DIR/MacSlap/SettingsView.swift"
    "$PROJECT_DIR/MacSlap/MenuBarView.swift"
    "$PROJECT_DIR/MacSlap/ChargerMonitor.swift"
)

swiftc \
    -parse-as-library \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreMotion \
    -framework IOKit \
    -framework UniformTypeIdentifiers \
    -O \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "${SWIFT_FILES[@]}"

echo "Compiled successfully"

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign
echo "Signing..."
codesign --force --sign - --entitlements "$PROJECT_DIR/MacSlap/MacSlap.entitlements" "$APP_BUNDLE"

echo "=== Build complete: $APP_BUNDLE ==="

# Create DMG
echo "=== Creating DMG ==="

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create a temporary folder for DMG contents
DMG_STAGING="$BUILD_DIR/dmg_staging"
mkdir -p "$DMG_STAGING"

# Copy app to staging
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create symlink to Applications
ln -s /Applications "$DMG_STAGING/Applications"

# Create the DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "=== Done! ==="
echo "DMG created at: $DMG_PATH"
echo ""
echo "To install: Open the DMG and drag MacSlap to Applications."
echo "The app runs in the menu bar (no Dock icon)."
