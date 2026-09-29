#!/usr/bin/env bash
# Send a build to Apple to be checked, then attach the result to it.
#
#     Scripts/notarize.sh "build/TheONE Light Practice.app"
#     Scripts/notarize.sh "build/TheONE Light Practice.dmg"
#
# Needs APPLE_ID, APP_PASSWORD and TEAM_ID in the environment. Apple checks the
# build for malware; once it passes, the approval is stapled on so it opens even
# without an internet connection.
#
# Both the app and the disk image around it get their own approval. Stapling only
# the disk image is enough for Gatekeeper to let it open, but the moment someone
# drags the app to their Applications folder the copy carries nothing, and a Mac
# that happens to be offline then has no way to check it.
set -euo pipefail

TARGET="${1:-build/TheONE Light Practice.dmg}"
: "${APPLE_ID:?APPLE_ID is not set}"
: "${APP_PASSWORD:?APP_PASSWORD is not set}"
: "${TEAM_ID:?TEAM_ID is not set}"

if [ ! -e "$TARGET" ]; then
  echo "Nothing to notarise at $TARGET" >&2
  exit 1
fi

# notarytool takes a disk image, an installer package, or a zip — not a bare app
# bundle. So an app is zipped up for the journey there. The approval comes back
# against the app's own signature, which is why it is stapled to the app and the
# zip is thrown away.
SUBMISSION="$TARGET"
SCRATCH=""
case "$TARGET" in
  *.app)
    SUBMISSION="${TARGET%.app}.zip"
    rm -f "$SUBMISSION"
    ditto -c -k --keepParent "$TARGET" "$SUBMISSION"
    SCRATCH="$SUBMISSION"
    ;;
esac

echo "Sending $SUBMISSION to Apple. This usually takes a few minutes."
xcrun notarytool submit "$SUBMISSION" \
  --apple-id "$APPLE_ID" \
  --password "$APP_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait \
  --timeout 30m

if [ -n "$SCRATCH" ]; then
  rm -f "$SCRATCH"
fi

echo "Attaching the approval..."
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

# Stapling an app writes the approval inside the bundle. Check the signature has
# survived that, because a broken one would otherwise only turn up on somebody
# else's Mac, long after the release went out.
case "$TARGET" in
  *.app)
    codesign --verify --strict --verbose=2 "$TARGET"
    echo "Signature still good after stapling."
    ;;
esac

echo "Done — $TARGET is ready to publish."
