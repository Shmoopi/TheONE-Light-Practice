#!/usr/bin/env bash
# Wrap the SPM executable in a real .app bundle.
#
# A bare SPM executable cannot be a proper macOS app: it has no Info.plist, so it
# gets no Dock icon, no menu bar, and no document-type registration for MIDI files.
# Building the bundle by hand keeps the project buildable with plain `swift build`
# and no Xcode project to maintain.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/TheONE Light Practice.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "note: Resources/AppIcon.icns missing — run make-icon.py to generate it" >&2
fi
cp "$BIN_DIR/TheOnePractice" "$APP/Contents/MacOS/TheONE Light Practice"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>TheONE Light Practice</string>
    <key>CFBundleDisplayName</key>          <string>TheONE Light Practice</string>
    <key>CFBundleExecutable</key>           <string>TheONE Light Practice</string>
    <key>CFBundleIdentifier</key>           <string>local.theone.lightpractice</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>     <string>MIDI File</string>
            <key>CFBundleTypeRole</key>     <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array><string>public.midi-audio</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature: unsigned bundles are killed on launch on Apple silicon.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

# Nudge Launch Services, or the Dock keeps showing a stale icon for the old path.
touch "$APP"
echo "built $APP"
