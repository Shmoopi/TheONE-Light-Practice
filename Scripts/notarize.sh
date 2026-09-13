#!/usr/bin/env bash
# Send a build to Apple to be checked, then attach the result to it.
#
#     Scripts/notarize.sh "build/TheONE Light Practice.dmg"
#
# Needs APPLE_ID, APP_PASSWORD and TEAM_ID in the environment. Apple checks the
# build for malware; once it passes, the approval is stapled on so it opens even
# without an internet connection.
set -euo pipefail

TARGET="${1:-build/TheONE Light Practice.dmg}"
: "${APPLE_ID:?APPLE_ID is not set}"
: "${APP_PASSWORD:?APP_PASSWORD is not set}"
: "${TEAM_ID:?TEAM_ID is not set}"

echo "Sending $TARGET to Apple. This usually takes a few minutes."
xcrun notarytool submit "$TARGET" \
  --apple-id "$APPLE_ID" \
  --password "$APP_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait \
  --timeout 30m

echo "Attaching the approval..."
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "Done — $TARGET is ready to publish."
