#!/bin/bash
# Builds КиноПохуй for this Mac (Release, only this Mac's architecture, signed to run here) and installs it as
# /Applications/КиноПохуй.app. The public universal build with the DMG and the update is scripts/release.sh.
# Needs Xcode at /Applications/Xcode.app (or DEVELOPER_DIR=…/Contents/Developer); it doesn't have to be the selected
# one. Usage: ./build-mac.sh [--no-launch]
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
DERIVED=${DERIVED:-$HOME/Library/Developer/KinoPohuy-build}
APP_ID=com.kinopohuy.mac
DEST="/Applications/КиноПохуй.app"
# Release is universal (arm64 + x86_64); a local install needs only this Mac's half, twice as fast.
ARCH=$(uname -m)

echo "Building…"
xcodebuild -project VideoLib.xcodeproj -scheme VideoLib -configuration Release \
  -destination "platform=macOS,arch=$ARCH" -derivedDataPath "$DERIVED" \
  ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -skipMacroValidation -skipPackagePluginValidation build > "$DERIVED.log" 2>&1 \
  || { grep -E "error:" "$DERIVED.log" | sort -u | head -20; echo "Build failed, log: $DERIVED.log"; exit 1; }

BUILT="$DERIVED/Build/Products/Release/KinoPohuy.app"
osascript -e "tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 || true
sleep 1

rm -rf "$DEST"
ditto "$BUILT" "$DEST"

# The executable keeps a Latin name (codesign trips over Cyrillic ones); the menu bar shows CFBundleName.
/usr/libexec/PlistBuddy -c "Set :CFBundleName КиноПохуй" "$DEST/Contents/Info.plist"
codesign -d --entitlements :- "$BUILT" > "$DERIVED/entitlements.plist" 2>/dev/null
# --generate-entitlement-der as Xcode does: without the DER copy the sandbox ignores the entitlements (no network).
codesign --force --sign - --generate-entitlement-der --entitlements "$DERIVED/entitlements.plist" "$DEST" 2>/dev/null

# Russian whatever the system's first language is (the app has its own strings in Russian).
PREFS="$HOME/Library/Containers/$APP_ID/Data/Library/Preferences/$APP_ID"
if [ -d "$(dirname "$PREFS")" ]; then
  defaults write "$PREFS" AppleLanguages -array ru
else
  defaults write "$APP_ID" AppleLanguages -array ru
fi

echo "Installed: $DEST"
[ "${1:-}" = "--no-launch" ] || open "$DEST"
