#!/bin/bash
# Builds a public release of КиноПохуй: one universal app (Apple Silicon + Intel, signed ad hoc, Russian everywhere)
# packed two ways, in build/release/<VERSION>/:
#   KinoPohuy-<VERSION>.zip  the Sparkle update; its EdDSA signature goes into docs/appcast.xml (GitHub Pages)
#   KinoPohuy.dmg            what people download from GitHub Releases; the same name in every release, so the README's
#                            «Скачать» link (releases/latest/download/KinoPohuy.dmg) always gets the newest one
# It publishes nothing: at the end it prints the SHA-256 sums and the publish steps (commit, `gh release create`, then
# the feed) to run yourself. docs/appcast.xml changes only once the zip and the DMG are both made and verified.
#
# Usage: scripts/release.sh VERSION [--skip-sign]
#   VERSION      2.0.0, 2.1.0… (MARKETING_VERSION). The build number (CFBundleVersion, the one Sparkle compares) is
#                the project's, or one more than the newest in docs/appcast.xml if that is already released.
#   --skip-sign  Dry run: no Sparkle key, no appcast, the project file stays as it is, placeholders only warn. It still
#                builds, signs ad hoc and makes the zip and the DMG.
#
# Once, before the first release:
#   1. Fill in VideoLib/Core/AppLinks.swift (repository, releases, appcast) and put the same appcast address into
#      VideoLib/Resources/Info.plist → SUFeedURL. Freeze them: every shipped copy asks that address for updates forever.
#   2. Make the update key (run this script once with --skip-sign so the Sparkle tools are downloaded, then):
#        BIN=/tmp/kinopohuy-release/dd/SourcePackages/artifacts/sparkle/Sparkle/bin
#        "$BIN/generate_keys" --account kinopohuy       # keeps the private key in the login keychain, prints the public one
#      Paste the printed public key into Info.plist → SUPublicEDKey (in place of SPARKLE_PUBLIC_KEY_PLACEHOLDER).
#      Back the private key up offline — losing it strands every install, it can't be rotated. Export it straight to
#      an encrypted place (a password manager, an encrypted disk image), not to a synced folder such as ~/Desktop:
#        "$BIN/generate_keys" --account kinopohuy -x /Volumes/<encrypted volume>/kinopohuy-ed25519.priv
#      Never put that file, or any *.priv / *.p12, inside this folder.
#   3. Write release-notes/<VERSION>.md (the GitHub release text and Sparkle's «what's new» dialog).
#   4. Optional: `brew install create-dmg` for the DMG with its background (scripts/dmg); without it, a plain DMG.
#      create-dmg drives Finder, so the first run asks to allow Terminal to control Finder.
#
# The app is built from a copy of the repository's files at a neutral path (BUILD_ROOT): Swift writes source paths
# (#filePath) into the binary, and a build from the home folder would publish the maintainer's user name.
#
# Env overrides: BUILD_ROOT (default /tmp/kinopohuy-release), DERIVED (DerivedData, default $BUILD_ROOT/dd), OUT_ROOT
# (default build/release), SPARKLE_BIN (the folder with generate_keys/generate_appcast/sign_update), DEVELOPER_DIR.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="КиноПохуй"
PRODUCT=KinoPohuy
KEY_ACCOUNT=kinopohuy
PBX=VideoLib.xcodeproj/project.pbxproj
PLIST=VideoLib/Resources/Info.plist
LINKS=VideoLib/Core/AppLinks.swift
APPCAST=docs/appcast.xml
KEY_PLACEHOLDER=SPARKLE_PUBLIC_KEY_PLACEHOLDER

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
BUILD_ROOT=${BUILD_ROOT:-/tmp/kinopohuy-release}
DERIVED=${DERIVED:-$BUILD_ROOT/dd}
SRC="$BUILD_ROOT/src"

step() { printf '\n→ %s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }
warn() { printf '! %s\n' "$*" >&2; }

VERSION=${1:-}
SKIP_SIGN=false
[ "${2:-}" = "--skip-sign" ] && SKIP_SIGN=true
[ $# -le 2 ] && { [ $# -lt 2 ] || $SKIP_SIGN; } || die "usage: scripts/release.sh VERSION [--skip-sign]"
[[ $VERSION =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "usage: scripts/release.sh VERSION [--skip-sign]  (VERSION like 2.0.0)"

OUT_ROOT=${OUT_ROOT:-build/release}
OUT="$OUT_ROOT/$VERSION"
NOTES="release-notes/$VERSION.md"

# In a real run a problem stops the release; in a dry run it's only reported.
problem() { if $SKIP_SIGN; then warn "$* (dry run: going on)"; else die "$*"; fi; }

# A link's value in AppLinks.swift: `static let NAME = URL(string: "…")!`.
link() { sed -nE "s/^[[:space:]]*static let $1 = URL\(string: \"([^\"]*)\"\)!.*/\1/p" "$LINKS" | head -1; }
# AppLinks.isSet's markers, plus _ADDRESS (an older wallet placeholder).
is_placeholder() { [[ -z $1 || $1 =~ (OWNER|REPO|CHANNEL|USERNAME|PAGE_ID|WALLET|_ADDRESS) ]]; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true; }

# ── 0. Preconditions ────────────────────────────────────────────────────────────────────────────────────────────
step "Checking links, keys and notes"

REPO_URL=$(link repository)
RELEASES_URL=$(link releases)
APPCAST_URL=$(link appcast)
FEED_URL=$(plist SUFeedURL "$PLIST")
ED_KEY=$(plist SUPublicEDKey "$PLIST")

is_placeholder "$REPO_URL" && problem "AppLinks.repository is still a placeholder"
is_placeholder "$RELEASES_URL" && problem "AppLinks.releases is still a placeholder"
is_placeholder "$APPCAST_URL" && problem "AppLinks.appcast is still a placeholder"
[[ $REPO_URL == https://github.com/* ]] || problem "AppLinks.repository isn't a github.com address (the downloads live in its Releases)"
[ "$FEED_URL" = "$APPCAST_URL" ] || problem "Info.plist SUFeedURL differs from AppLinks.appcast"
[[ -n $ED_KEY && $ED_KEY != "$KEY_PLACEHOLDER" ]] || problem "Info.plist SUPublicEDKey is still $KEY_PLACEHOLDER (see the header of this script)"
[ -f "$NOTES" ] || problem "$NOTES is missing (it's the release text and Sparkle's «what's new»)"

# The public app carries no site address: people type it in at first launch.
grep -Eq 'static let mirror\b.*example\.invalid' VideoLib/Core/Const.swift || die "Const.mirror must stay the placeholder address"

# The release is tagged on HEAD, so HEAD must hold exactly what gets built (the build copies the working tree).
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git checkout (the build copies the files git would publish)"
DIRTY=$(git status --porcelain -- . ":(exclude)$APPCAST" ":(exclude)$PBX")
[ -z "$DIRTY" ] || problem "uncommitted changes would ship without being in the tag; commit them first:"$'\n'"$DIRTY"

# aria2's source (GPL): the exact tarball scripts/aria2/build.sh built the bundled aria2c from; it goes up with the
# release. Fetched from the pinned address when build/ was cleaned (no rebuild, so the recorded sums stay valid).
ARIA2_VERSION=$(sed -n 's/^VERSION=//p' scripts/aria2/build.sh)
ARIA2_SHA=$(sed -n 's/^SHA256=//p' scripts/aria2/build.sh)
ARIA2_TARBALL="aria2-$ARIA2_VERSION.tar.xz"
if [ ! -f "build/aria2/$ARIA2_TARBALL" ]; then
  mkdir -p build/aria2
  curl -fL --retry 3 -o "build/aria2/$ARIA2_TARBALL.part" \
    "https://github.com/aria2/aria2/releases/download/release-$ARIA2_VERSION/$ARIA2_TARBALL" \
    && mv "build/aria2/$ARIA2_TARBALL.part" "build/aria2/$ARIA2_TARBALL" || die "couldn't download $ARIA2_TARBALL"
fi
echo "$ARIA2_SHA  build/aria2/$ARIA2_TARBALL" | shasum -a 256 -c - >/dev/null || die "build/aria2/$ARIA2_TARBALL doesn't match scripts/aria2/build.sh"
grep -qx "### aria2 $ARIA2_VERSION" THIRD_PARTY_NOTICES.md && grep -q "version: \"$ARIA2_VERSION\"" VideoLib/Presentations/Components/LicensesView.swift \
  || die "aria2's version in THIRD_PARTY_NOTICES.md or LicensesView.swift isn't $ARIA2_VERSION"

# Old public builds are below this one only if the number keeps growing.
CUR_BUILD=$(sed -nE 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/p' "$PBX" | sort -n | tail -1)
LAST_BUILD=0
if [ -f "$APPCAST" ]; then
  LAST_BUILD=$(sed -nE 's/.*<sparkle:version>([0-9]+)<\/sparkle:version>.*/\1/p' "$APPCAST" | sort -n | tail -1)
  LAST_BUILD=${LAST_BUILD:-0}
  grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST" \
    && problem "$VERSION is already in $APPCAST"
fi
BUILD=$(( CUR_BUILD > LAST_BUILD ? CUR_BUILD : LAST_BUILD + 1 ))
echo "  version $VERSION, build $BUILD (project $CUR_BUILD, last released $LAST_BUILD)"

rm -rf "$OUT"
mkdir -p "$OUT/stage" "$OUT/updates"
LOG="$OUT/build.log"

# A fresh SourcePackages: the licenses window is made from its workspace-state.json, which keeps packages an older
# version of the project checked out. Resolving again downloads only what Package.resolved pins.
step "Resolving packages from scratch (Sparkle's tools come with them)"
[ -n "$DERIVED" ] && rm -rf "$DERIVED/SourcePackages"
xcodebuild -resolvePackageDependencies -project VideoLib.xcodeproj -scheme VideoLib -derivedDataPath "$DERIVED" > "$LOG" 2>&1 \
  || { tail -20 "$LOG"; die "package resolution failed, log: $LOG"; }

BIN=${SPARKLE_BIN:-$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin}
if ! $SKIP_SIGN; then
  for tool in generate_keys generate_appcast sign_update; do
    [ -x "$BIN/$tool" ] || die "Sparkle's $tool isn't in $BIN"
  done
  KEYCHAIN_KEY=$("$BIN/generate_keys" --account "$KEY_ACCOUNT" -p 2>/dev/null) \
    || die "no update key in the keychain for --account $KEY_ACCOUNT (see the header of this script)"
  [ "$KEYCHAIN_KEY" = "$ED_KEY" ] || die "Info.plist SUPublicEDKey isn't the keychain's key for --account $KEY_ACCOUNT"
fi

# ── 1. Version ──────────────────────────────────────────────────────────────────────────────────────────────────
if $SKIP_SIGN; then
  step "Version $VERSION ($BUILD) for this build only (dry run: the project file is untouched)"
else
  step "Setting the project to $VERSION ($BUILD)"
  sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/" "$PBX"
  [ "$(grep -c "CURRENT_PROJECT_VERSION = $BUILD;" "$PBX")" = 2 ] && [ "$(grep -c "MARKETING_VERSION = $VERSION;" "$PBX")" = 2 ] \
    || die "couldn't set the version in $PBX"
fi

# ── 2. Build: universal, Release, ad hoc ────────────────────────────────────────────────────────────────────────
step "Building (Release, arm64 + x86_64; a few minutes)"
# Exactly the files that would be published (tracked or not ignored), with the version just set.
rm -rf "$SRC"
mkdir -p "$SRC"
# Only paths that exist: a tracked file deleted without `git rm` would make rsync stop.
git ls-files -co --exclude-standard -z \
  | while IFS= read -r -d '' f; do if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi; done \
  | rsync -a --from0 --files-from=- ./ "$SRC/" || die "copying the sources to $SRC failed"
xcodebuild -project "$SRC/VideoLib.xcodeproj" -scheme VideoLib -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -skipMacroValidation -skipPackagePluginValidation clean build >> "$LOG" 2>&1 \
  || { grep -E "error:" "$LOG" | sort -u | head -20; die "build failed, log: $LOG"; }

BUILT="$DERIVED/Build/Products/Release/$PRODUCT.app"
[ -d "$BUILT" ] || die "no $BUILT"
# grep -c reads to the end: with -q, strings would die of SIGPIPE and pipefail would hide the match.
HOME_PATHS=$(strings -a "$BUILT/Contents/MacOS/$PRODUCT" | grep -cF "$HOME/" || true)
[ "$HOME_PATHS" = 0 ] || die "the binary carries $HOME_PATHS paths from the home folder: set BUILD_ROOT outside $HOME"

# ── 3. Stage: name, Russian only, signature ─────────────────────────────────────────────────────────────────────
# Everything that changes the bundle happens before the last codesign: an update with a broken signature is refused.
step "Staging $APP_NAME.app"
APP="$OUT/stage/$APP_NAME.app"
ditto "$BUILT" "$APP"

# The executable keeps its Latin name (codesign trips over Cyrillic ones); the menu bar shows CFBundleName.
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion ru" "$APP/Contents/Info.plist"

# Only ru.lproj stays, so the app (and Sparkle's dialogs, which follow the app's language) is Russian on any Mac.
[ -d "$APP/Contents/Resources/ru.lproj" ] || die "the build has no ru.lproj"
find "$APP/Contents/Resources" -maxdepth 1 -name '*.lproj' ! -name 'ru.lproj' ! -name 'Base.lproj' -exec rm -rf {} +

# The recommender's open data pack (scripts/datapack: Wikidata's critics and ids, viewer neighbours), built on this
# Mac and kept out of git; the app reads it from its Resources.
PACK=build/datapack/recs-pack.sqlite
if [ -f "$PACK" ]; then
  cp "$PACK" "$APP/Contents/Resources/recs-pack.sqlite"
  echo "  data pack: $(sqlite3 -readonly "$PACK" "select value from meta where key = 'built'") ($(du -h "$PACK" | cut -f1 | tr -d ' '))"
elif $SKIP_SIGN; then
  warn "no data pack ($PACK): the app goes without critics' scores and viewer suggestions"
else
  die "no data pack: run scripts/datapack/wikidata.py, the neighbours step and build_pack.py (see scripts/datapack)"
fi

xattr -cr "$APP"

# Xcode's own entitlements, with $(PRODUCT_BUNDLE_IDENTIFIER) already expanded (Sparkle's -spks/-spki lookups).
codesign -d --entitlements - --xml "$BUILT" > "$OUT/entitlements.plist" 2>/dev/null
grep -q 'com.kinopohuy.mac-spks' "$OUT/entitlements.plist" && grep -q 'com.kinopohuy.mac-spki' "$OUT/entitlements.plist" \
  || die "the built app lacks Sparkle's mach-lookup entitlements"
grep -q 'com.apple.security.app-sandbox' "$OUT/entitlements.plist" || die "the built app isn't sandboxed"
grep -q 'get-task-allow' "$OUT/entitlements.plist" && die "the built app is debuggable (get-task-allow): not a Release build?"

# --generate-entitlement-der as Xcode does: without the DER copy the sandbox ignores the entitlements (no network).
codesign --force --sign - --generate-entitlement-der --entitlements "$OUT/entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP" || die "the signature doesn't verify"

info() { plist "$1" "$APP/Contents/Info.plist"; }
[ "$(info CFBundleShortVersionString)" = "$VERSION" ] || die "CFBundleShortVersionString isn't $VERSION"
[ "$(info CFBundleVersion)" = "$BUILD" ] || die "CFBundleVersion isn't $BUILD"
[ "$(info CFBundleName)" = "$APP_NAME" ] || die "CFBundleName isn't $APP_NAME"
[ "$(info SUEnableInstallerLauncherService)" = true ] || die "SUEnableInstallerLauncherService is off (needed in the sandbox)"
[ "$(info SUFeedURL)" = "$FEED_URL" ] || die "SUFeedURL in the app differs from Info.plist"
ARCHS_BUILT=$(lipo -archs "$APP/Contents/MacOS/$PRODUCT")
[[ $ARCHS_BUILT == *arm64* && $ARCHS_BUILT == *x86_64* ]] || die "not universal: $ARCHS_BUILT"
[ -f "$APP/Contents/Resources/aria2c-arm64" ] && [ -f "$APP/Contents/Resources/aria2c-x86_64" ] || die "aria2c is missing"
# aria2c must be the project's own build (scripts/aria2/build.sh, ad hoc), never a third party's prebuilt binary:
# its GPL source is the tarball attached to the release.
# grep -c, not -q, here too: codesign would die of SIGPIPE and pipefail would read it as a mismatch.
for ARIA2 in "$APP/Contents/Resources/aria2c-arm64" "$APP/Contents/Resources/aria2c-x86_64"; do
  NAME=$(basename "$ARIA2")
  [ "$(codesign -dv "$ARIA2" 2>&1 | grep -c '^TeamIdentifier=not set')" = 1 ] || die "$NAME isn't the project's own build (run scripts/aria2/build.sh)"
  SUM=$(shasum -a 256 "$ARIA2" | cut -d' ' -f1)
  grep -qF "\`$NAME\`: \`$SUM\`" THIRD_PARTY_NOTICES.md || die "$NAME isn't the build recorded in THIRD_PARTY_NOTICES.md (rebuilt? update the sums)"
  [ "$(otool -L "$ARIA2" | tail -n +2 | grep -cvE '^[[:space:]]+(/usr/lib/|/System/Library/)')" = 0 ] || die "$NAME links a library outside macOS"
done
echo "  $ARCHS_BUILT, $(info CFBundleShortVersionString) ($(info CFBundleVersion)), signed ad hoc, verified"

# ── 4. The Sparkle update ───────────────────────────────────────────────────────────────────────────────────────
# ASCII file names: GitHub mangles Cyrillic asset names. ditto keeps the frameworks' symlinks (zip -r breaks them).
step "Packing the update"
ZIP_NAME="$PRODUCT-$VERSION.zip"
ZIP="$OUT/updates/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir -p "$OUT/check"
ditto -x -k "$ZIP" "$OUT/check"
codesign --verify --deep --strict "$OUT/check/$APP_NAME.app" || die "the app inside the zip doesn't verify"
rm -rf "$OUT/check"

if $SKIP_SIGN; then
  step "Skipping the appcast (dry run: no key)"
else
  step "Signing it into a new feed (it replaces $APPCAST once the DMG is verified too)"
  # generate_appcast reuses the appcast it finds next to the archives: the old items stay, the new one is added and
  # signed with the keychain's key. Release notes: the .md with the archive's name, embedded in the item.
  cp "$NOTES" "$OUT/updates/$PRODUCT-$VERSION.md"
  [ -f "$APPCAST" ] && cp "$APPCAST" "$OUT/updates/appcast.xml"
  "$BIN/generate_appcast" --account "$KEY_ACCOUNT" \
    --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" --link "$REPO_URL" \
    --embed-release-notes --maximum-deltas 0 -o "$OUT/updates/appcast.xml" "$OUT/updates" \
    || die "generate_appcast failed"
  grep -q "<sparkle:version>$BUILD</sparkle:version>" "$OUT/updates/appcast.xml" \
    || die "generate_appcast added no item for build $BUILD (it skips builds not above the feed's newest)"
  grep -q "$REPO_URL/releases/download/v$VERSION/$ZIP_NAME" "$OUT/updates/appcast.xml" || die "the item's download address is wrong"

  SIG=$(xmllint --xpath "string(//*[local-name()='item'][*[local-name()='version']='$BUILD']/*[local-name()='enclosure']/@*[local-name()='edSignature'])" "$OUT/updates/appcast.xml")
  [ -n "$SIG" ] || die "the new item has no EdDSA signature"
  "$BIN/sign_update" --account "$KEY_ACCOUNT" --verify "$ZIP" "$SIG" >/dev/null || die "the zip's signature doesn't verify"
  echo "  signed and verified: $OUT/updates/appcast.xml"
fi

# ── 5. The DMG ──────────────────────────────────────────────────────────────────────────────────────────────────
step "Making the DMG"
# No version in the name: GitHub's releases/latest/download/<name> link only works when every release uses the same one
# (the folder is per version, so nothing is overwritten).
DMG_NAME="$PRODUCT.dmg"
DMG="$OUT/$DMG_NAME"
BACKGROUND=scripts/dmg/background.tiff
[ -f "$BACKGROUND" ] || DEVELOPER_DIR="$DEVELOPER_DIR" swift scripts/dmg/make-background.swift >/dev/null || warn "no DMG background"

MADE=false
if command -v create-dmg >/dev/null && [ -f "$BACKGROUND" ]; then
  VOLICON=()
  [ -f "$APP/Contents/Resources/$PRODUCT.icns" ] && VOLICON=(--volicon "$APP/Contents/Resources/$PRODUCT.icns")
  # Same layout as scripts/dmg/make-background.swift: the app at (170, 200), «Программы» at (490, 200).
  if create-dmg --volname "$APP_NAME" ${VOLICON[@]+"${VOLICON[@]}"} --background "$BACKGROUND" \
      --window-pos 200 120 --window-size 660 420 --icon-size 128 --text-size 13 \
      --icon "$APP_NAME.app" 170 200 --app-drop-link 490 200 \
      "$DMG" "$OUT/stage" >> "$LOG" 2>&1; then
    MADE=true
  else
    warn "create-dmg failed (Finder automation not allowed?), making a plain DMG; log: $LOG"
    rm -f "$DMG" "$OUT"/rw.*.dmg
  fi
else
  echo "  create-dmg isn't installed: a plain DMG (the app and a «Программы» link, no background)"
fi

if ! $MADE; then
  ln -s /Applications "$OUT/stage/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >> "$LOG" 2>&1 \
    || { rm -f "$OUT/stage/Applications"; die "hdiutil create failed, log: $LOG"; }
  rm -f "$OUT/stage/Applications"
fi

hdiutil verify "$DMG" >> "$LOG" 2>&1 || die "the DMG doesn't verify"

# The app inside the image must still verify (Finder copies exactly this).
MNT="$OUT/mnt"
mkdir -p "$MNT"
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MNT" >> "$LOG" 2>&1 || die "can't mount the DMG"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true' EXIT
codesign --verify --deep --strict "$MNT/$APP_NAME.app" || die "the app inside the DMG doesn't verify"
[ -L "$MNT/Applications" ] || die "the DMG has no «Программы» link"
hdiutil detach "$MNT" -quiet
trap - EXIT
rmdir "$MNT"

# ── 6. The feed, sums and what's next ───────────────────────────────────────────────────────────────────────────
# Only now, with the zip and the DMG both verified: a run that stopped earlier leaves docs/appcast.xml as it was.
if ! $SKIP_SIGN; then
  mkdir -p docs
  cp "$OUT/updates/appcast.xml" "$APPCAST"
  echo "  $APPCAST updated (commit it last, after the release files are uploaded)"
fi

cp "build/aria2/$ARIA2_TARBALL" "$OUT/$ARIA2_TARBALL"

(cd "$OUT" && shasum -a 256 "$DMG_NAME" "updates/$ZIP_NAME" "$ARIA2_TARBALL" | sed 's#updates/##' > SHA256SUMS.txt)

step "Done: $OUT"
cat "$OUT/SHA256SUMS.txt"

SLUG=${REPO_URL#https://github.com/}
is_placeholder "$REPO_URL" && SLUG="OWNER/REPO"
if $SKIP_SIGN; then
  echo
  echo "Nothing was published (dry run: the zip isn't in any feed and the project file wasn't changed; don't upload these files)."
else
  cat <<EOF

Nothing was published. Next, in this order (the feed last, so it never points at a missing file):
  1. Commit and push the version bump (the release is tagged on this commit):
     git add $PBX && { git diff --cached --quiet || git commit -m "$APP_NAME $VERSION"; } && git push
  2. Create the release on that commit, with its files:
     gh release create v$VERSION --repo $SLUG --target "\$(git rev-parse HEAD)" --title "$APP_NAME $VERSION" \\
       --notes-file $NOTES "$DMG" "$ZIP" "$OUT/$ARIA2_TARBALL" "$OUT/SHA256SUMS.txt"
  3. Only then commit and push the feed; GitHub Pages serves it within ~10 minutes:
     git add $APPCAST && git commit -m "appcast: $VERSION" && git push
  4. Before announcing: install the DMG on another Mac (or user), open it via «Всё равно открыть», and check that
     «Проверить наличие обновлений…» finds nothing newer.
EOF
fi
