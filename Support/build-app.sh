#!/bin/zsh
# builds the .app and signs it with a STABLE identity.
# the tcc (accessibility) permission is tied to the code signature's "designated requirement".
# with ad-hoc signing that's the binary's hash, which changes every build; with an apple
# development certificate it's bundle id + certificate name, so it stays the same and the
# permission survives rebuilds.
set -euo pipefail

ROOT=${0:A:h:h}
CONFIG=${CONFIG:-release}
SIGN_IDENTITY=${SIGN_IDENTITY:-"Apple Development"}
# RELEASE=1: universal binary, hardened runtime and a secure timestamp, as notarization needs.
RELEASE=${RELEASE:-0}
APP="$ROOT/build/BetterGestures.app"

if [[ $RELEASE == 1 ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
    SIGN_FLAGS=(--options runtime --timestamp)
else
    ARCH_FLAGS=(--arch arm64)
    SIGN_FLAGS=(--timestamp=none)
fi

cd "$ROOT"
swift build -c "$CONFIG" $ARCH_FLAGS
BIN_DIR=$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/BetterGestures" "$APP/Contents/MacOS/BetterGestures"

# translations: compile the string catalog into .lproj files (xcstringstool comes with xcode).
RESOURCES="$APP/Contents/Resources"
mkdir -p "$RESOURCES"
if xcrun --find xcstringstool >/dev/null 2>&1; then
    xcrun xcstringstool compile Support/Localizable.xcstrings --output-directory "$RESOURCES"
    # keys are turkish; without tr.lproj the system picks english for turkish users.
    mkdir -p "$RESOURCES/tr.lproj"
else
    echo "warning: xcstringstool not found (comes with xcode); the app will only be in turkish" >&2
fi

codesign --force $SIGN_FLAGS --sign "$SIGN_IDENTITY" "$APP"

codesign --verify --strict --deep "$APP"
echo "signed: $APP"
codesign -d --requirements - "$APP" 2>/dev/null | sed -n 's/^designated => /  designated requirement: /p'
