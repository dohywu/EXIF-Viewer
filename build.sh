#!/bin/bash
# Builds Metadata Inspector.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Metadata Inspector"
BIN="EXIFViewer"
DIST="dist"
BUNDLE="$DIST/$APP_NAME.app"

echo "▸ release build"
swift build -c release --disable-sandbox

echo "▸ assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$BIN" "$BUNDLE/Contents/MacOS/$BIN"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "▸ signing (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE" >/dev/null

if [ "${1:-}" = "--install" ]; then
  pkill -f "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$BUNDLE" /Applications/
  echo "✓ /Applications/$APP_NAME.app"
else
  echo "✓ $BUNDLE   (install: ./build.sh --install)"
fi
