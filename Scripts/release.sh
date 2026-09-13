#!/usr/bin/env bash
# Build the app, sign it, and wrap it in a disk image ready for release.
#
#     Scripts/release.sh "Developer ID Application: Your Name (TEAMID)" TEAMID
#
# Run without arguments for a local unsigned build, which is fine for testing but
# will not open on anyone else's Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${1:-}"
TEAM_ID="${2:-}"
APP="build/TheONE Light Practice.app"
DMG="build/TheONE Light Practice.dmg"

Scripts/bundle.sh release

if [ -z "$IDENTITY" ]; then
  echo "No signing identity given — this build is for local use only."
else
  echo "Signing with: $IDENTITY"

  # Hardened runtime is required for notarising. The entitlement lets the app
  # talk to your keyboard over USB MIDI.
  cat > build/entitlements.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.usb</key>      <true/>
    <key>com.apple.security.files.user-selected.read-only</key> <true/>
</dict>
</plist>
PLIST

  codesign --force --deep --options runtime --timestamp \
    --entitlements build/entitlements.plist \
    --sign "$IDENTITY" "$APP"

  codesign --verify --strict --verbose=2 "$APP"
  echo "Signature verified."
fi

echo "Building the disk image..."
rm -f "$DMG"
STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # so it can be dragged across

hdiutil create -volname "TheONE Light Practice" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

echo "Built $DMG"
