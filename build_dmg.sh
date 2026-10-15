#!/usr/bin/env bash
# ============================================================
#  build_dmg.sh — Build .env One Click Miner and package as DMG
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
DEV_ADDRESS="ZFdwFWvEypMVUAPygLRJ7ossTTqX8WZGJUs5b7AYEvvPSjsGdn836AhFyDP1n2JoKHgXAJNxWXDthJsfBPB2mnGoMt2Tc"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  .env Blocknet Miner DMG Builder                         ║"
echo "║  Real-time BNTpool.com telemetry & native Argon2id       ║"
echo "╚══════════════════════════════════════════════════════════╝"
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
  "$PROJECT_DIR/ZycordMiner/WalletGenerator.swift" \
  -o "$BUILD_DIR/$BUNDLE_NAME"

echo "→ Assembling $BUNDLE_NAME.app bundle…"
APP_BUNDLE="$BUILD_DIR/$BUNDLE_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/en.lproj"

cp "$BUILD_DIR/$BUNDLE_NAME" "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME"

for bin in seine xmrig; do
    if [[ -f "$PROJECT_DIR/${bin}" ]]; then
        echo "  -> Bundling ${bin}..."
        cp "$PROJECT_DIR/${bin}" "$APP_BUNDLE/Contents/MacOS/${bin}"
        chmod +x "$APP_BUNDLE/Contents/MacOS/${bin}"
        ln -sf "../MacOS/${bin}" "$APP_BUNDLE/Contents/Resources/${bin}"
        codesign -s - --force "$APP_BUNDLE/Contents/MacOS/${bin}"
    fi
done

cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/ZycordMiner/ZycordMiner/Assets.xcassets/Logo.imageset/logo.png" "$APP_BUNDLE/Contents/Resources/Logo.png"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

cat << EOF > "$APP_BUNDLE/Contents/Resources/en.lproj/InfoPlist.strings"
CFBundleDisplayName = "$APP_NAME";
CFBundleName = "$APP_NAME";
EOF

cat << EOF > "$APP_BUNDLE/Contents/Info.plist"
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

echo "→ Ad-hoc code signing app bundle…"
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
  -volname ".env Miner" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

cp "$DMG_OUT" "$PROJECT_DIR/DotEnv-${VERSION}.dmg"
cp "$DMG_OUT" "$DMG_DIR/env-${VERSION}.dmg"
if [[ -d "$HOME/Desktop" ]]; then
  cp "$DMG_OUT" "$HOME/Desktop/DotEnv-${VERSION}.dmg"
  cp "$DMG_OUT" "$HOME/Desktop/env-${VERSION}.dmg"
  echo "→ Copied visible DMGs to Desktop:"
  echo "  - $HOME/Desktop/DotEnv-${VERSION}.dmg"
  echo "  - $HOME/Desktop/env-${VERSION}.dmg"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Build Complete!                         ║"
echo "║  DMG: $DMG_OUT"
echo "║  Desktop: $HOME/Desktop/DotEnv-${VERSION}.dmg"
echo "╚══════════════════════════════════════════╝"
echo ""
