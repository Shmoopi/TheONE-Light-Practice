#!/usr/bin/env bash
# Build the app, sign it, and wrap it in a disk image ready for release.
#
#     Scripts/release.sh "Developer ID Application: Your Name (TEAMID)" TEAMID
#
# Run without arguments for a local unsigned build, which is fine for testing but
# will not open on anyone else's Mac.
#
# For a real release the work splits in two, because the app needs Apple's
# approval attached to it *before* it is sealed into the disk image. A disk image
# is read-only once built, so an app packaged first can never be given its own
# approval afterwards — and that app is the thing people end up running.
#
#     Scripts/release.sh app "identity" TEAMID    # build and sign the app
#     Scripts/notarize.sh "build/TheONE Light Practice.app"
#     Scripts/release.sh dmg "identity" TEAMID    # wrap the approved app up
#     Scripts/notarize.sh "build/TheONE Light Practice.dmg"
#
# Given no stage it does both halves in one go, which is what you want locally.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="all"
case "${1:-}" in
  app|dmg|all) STAGE="$1"; shift ;;
esac

IDENTITY="${1:-}"
TEAM_ID="${2:-}"
APP="build/TheONE Light Practice.app"
DMG="build/TheONE Light Practice.dmg"

# ------------------------------------------------------- the app itself

if [ "$STAGE" = "app" ] || [ "$STAGE" = "all" ]; then
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
fi

# ------------------------------------------------------- the disk image

if [ "$STAGE" = "dmg" ] || [ "$STAGE" = "all" ]; then
  if [ ! -d "$APP" ]; then
    echo "No app at $APP — run the 'app' stage first." >&2
    exit 1
  fi

  echo "Building the disk image..."
  rm -f "$DMG"
  STAGE_DIR="build/dmg"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR"
  # -R rather than a move, so the approved app stays where notarize.sh left it.
  cp -R "$APP" "$STAGE_DIR/"
  ln -s /Applications "$STAGE_DIR/Applications"   # so it can be dragged across

  hdiutil create -volname "TheONE Light Practice" \
    -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE_DIR"

  if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
  fi

  echo "Built $DMG"
fi
