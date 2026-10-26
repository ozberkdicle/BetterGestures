#!/bin/zsh
# builds a universal, developer id signed and notarized zip for a github release.
# one-time setup:
#   - a "Developer ID Application" certificate in the keychain (xcode → settings → accounts →
#     manage certificates → + → developer id application)
#   - a notarytool profile: xcrun notarytool store-credentials BetterGestures --apple-id <apple id> --team-id <team id>
set -euo pipefail

ROOT=${0:A:h:h}
PROFILE=${NOTARY_PROFILE:-BetterGestures}
APP="$ROOT/build/BetterGestures.app"

cd "$ROOT"
SIGN_IDENTITY="Developer ID Application" RELEASE=1 ./Support/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$ROOT/build/BetterGestures-$VERSION.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "notarizing, this usually takes a minute or two…"
RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait)
echo "$RESULT"
if ! grep -q "status: Accepted" <<< "$RESULT"; then
    echo "notarization failed; see the log: xcrun notarytool log <id> --keychain-profile $PROFILE" >&2
    exit 1
fi

# staple the ticket into the app so it opens offline too, then zip the stapled app again.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
echo "ready: $ZIP"
