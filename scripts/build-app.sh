#!/bin/bash
# Builds build/Grove.app. Pass --install to copy it into ~/Applications.
# Set GROVE_VERSION (e.g. 1.2.0) to stamp a version over the one in Info.plist, and
# GROVE_SIGN_IDENTITY to a "Developer ID Application" identity to sign it for other Macs.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP=build/Grove.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Grove" "$APP/Contents/MacOS/Grove"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${GROVE_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$GROVE_VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$GROVE_VERSION" "$APP/Contents/Info.plist"
fi

if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${GROVE_SIGN_IDENTITY:-}" ]; then
  # Notarization requires the hardened runtime and a secure timestamp.
  codesign --force --options runtime --timestamp --sign "$GROVE_SIGN_IDENTITY" "$APP" >/dev/null
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/Grove.app
  cp -R "$APP" ~/Applications/Grove.app
  echo "Installed to ~/Applications/Grove.app"
fi
