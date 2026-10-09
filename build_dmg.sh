#!/usr/bin/env bash
# ============================================================
#  build_dmg.sh — Build .env (Zycord Miner) and package as DMG
#
#  Usage:
#    ./build_dmg.sh
# ============================================================

set -euo pipefail

APP_NAME=".env"
BUNDLE_NAME="DotEnv"
VERSION="1.0.0"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$PROJECT_DIR/dist"
DEV_ADDRESS="0x027fe1ebf286b8a862cb080c47d2bce0457b92c77b785812cabe88eb71ea4d44"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  .env (Zycord Miner) DMG Builder         ║"
echo "║  1 % developer fee — transparent         ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  App name  : $APP_NAME"
echo "  Version   : $VERSION"
echo "  Dev addr  : $DEV_ADDRESS"
echo ""

mkdir -p "$BUILD_DIR" "$DMG_DIR" "$PROJECT_DIR/.cache/clang"

echo "→ Compiling Swift sources with swiftc…"
swiftc -O -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -swift-version 5 \
  -module-cache-path "$PROJECT_DIR/.cache/clang" \
  "$PROJECT_DIR/ZycordMiner/ZycordMinerApp.swift" \
  "$PROJECT_DIR/ZycordMiner/ContentView.swift" \
  "$PROJECT_DIR/ZycordMiner/MinerManager.swift" \
  "$PROJECT_DIR/ZycordMiner/SetupManager.swift" \
  -o "$BUILD_DIR/$BUNDLE_NAME"

echo "→ Assembling $BUNDLE_NAME.app bundle…"
APP_BUNDLE="$BUILD_DIR/$BUNDLE_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$BUNDLE_NAME" "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME"

if [[ -f "$PROJECT_DIR/xmrig" ]]; then
    cp "$PROJECT_DIR/xmrig" "$APP_BUNDLE/Contents/MacOS/xmrig"
    chmod +x "$APP_BUNDLE/Contents/MacOS/xmrig"
    cp "$PROJECT_DIR/xmrig" "$APP_BUNDLE/Contents/Resources/xmrig"
    chmod +x "$APP_BUNDLE/Contents/Resources/xmrig"
    codesign -s - --force "$APP_BUNDLE/Contents/MacOS/xmrig"
    codesign -s - --force "$APP_BUNDLE/Contents/Resources/xmrig"
fi

cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/ZycordMiner/ZycordMiner/Assets.xcassets/Logo.imageset/logo.png" "$APP_BUNDLE/Contents/Resources/Logo.png"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

cat << EOF > "$APP_BUNDLE/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BUNDLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.dotenv.miner</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. MIT License.</string>
</dict>
</plist>
EOF

echo "→ Ad-hoc code signing…"
codesign -s - --force --deep "$APP_BUNDLE"

echo "→ Staging for DMG…"
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_OUT="$DMG_DIR/DotEnv-${VERSION}.dmg"
rm -f "$DMG_OUT"

echo "→ Creating DMG image…"
hdiutil create \
  -volname "DotEnv-Miner" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Build Complete!                         ║"
printf "║  DMG: %-35s║\n" "$DMG_OUT"
echo "╚══════════════════════════════════════════╝"
echo ""
