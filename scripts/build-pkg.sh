#!/bin/bash
# Builds build/Grove.pkg, an installer that puts Grove.app in /Applications.
# Pass a version (e.g. 1.2.0) to stamp it into the app and the installer. Set
# GROVE_SIGN_IDENTITY (see build-app.sh) and GROVE_INSTALLER_IDENTITY, a
# "Developer ID Installer" identity, to sign both for other Macs.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
GROVE_VERSION="$VERSION" ./scripts/build-app.sh

STAGE=build/pkg
rm -rf "$STAGE" build/Grove.pkg
mkdir -p "$STAGE/root"
ditto build/Grove.app "$STAGE/root/Grove.app"

# Without this, Installer "upgrades" any other Grove.app it finds (say, build/Grove.app)
# in place instead of putting a fresh copy in /Applications.
pkgbuild --analyze --root "$STAGE/root" "$STAGE/components.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$STAGE/components.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "$STAGE/components.plist"

pkgbuild --root "$STAGE/root" \
  --component-plist "$STAGE/components.plist" \
  --identifier app.grove.Grove \
  --version "$VERSION" \
  --install-location /Applications \
  "$STAGE/Grove-component.pkg" >/dev/null

# The binary is arm64 only and needs macOS 26, so the installer refuses anything else
# up front rather than leaving an app that won't open.
cat > "$STAGE/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Grove</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="26.0"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="app.grove.Grove"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="app.grove.Grove" visible="false">
        <pkg-ref id="app.grove.Grove"/>
    </choice>
    <pkg-ref id="app.grove.Grove" version="$VERSION" onConclusion="none">Grove-component.pkg</pkg-ref>
</installer-gui-script>
EOF

if [ -n "${GROVE_INSTALLER_IDENTITY:-}" ]; then
  productbuild --distribution "$STAGE/distribution.xml" \
    --package-path "$STAGE" \
    --sign "$GROVE_INSTALLER_IDENTITY" --timestamp \
    build/Grove.pkg >/dev/null
else
  productbuild --distribution "$STAGE/distribution.xml" \
    --package-path "$STAGE" \
    build/Grove.pkg >/dev/null
fi
echo "Built build/Grove.pkg ($VERSION)"
