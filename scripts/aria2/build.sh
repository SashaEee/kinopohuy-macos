#!/bin/bash
# Builds the aria2c that ships inside the app (VideoLib/Resources/aria2c-arm64 and aria2c-x86_64) from aria2's own
# release tarball, pinned by SHA-256 (the same hash Homebrew pins).
#
# Deliberately minimal: the app only drives plain HTTP(S) downloads over aria2's local JSON-RPC, so aria2c links
# nothing but macOS's own libraries (AppleTLS from Security.framework for HTTPS, the system libz). No BitTorrent,
# Metalink, SFTP, XML-RPC, WebSocket, async DNS or browser-cookie import: no third-party libraries to ship, license
# or keep patched. The complete corresponding source is that tarball plus this script.
#
# Usage: scripts/aria2/build.sh   (needs Xcode or its command line tools; a few minutes)
# The tarball is kept in build/aria2/ — scripts/release.sh attaches it to the GitHub release (GPL source).
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=1.37.0
SHA256=60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b
TARBALL="aria2-$VERSION.tar.xz"
URL="https://github.com/aria2/aria2/releases/download/release-$VERSION/$TARBALL"
MIN_MACOS=15.0
WORK=build/aria2
OUT=VideoLib/Resources

export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
# The toolchain's clang, called directly, doesn't know the SDK on its own.
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export SDKROOT

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

mkdir -p "$WORK"
if [ ! -f "$WORK/$TARBALL" ]; then
  echo "→ Downloading $TARBALL"
  curl -fL --retry 3 -o "$WORK/$TARBALL.part" "$URL"
  mv "$WORK/$TARBALL.part" "$WORK/$TARBALL"
fi
echo "$SHA256  $WORK/$TARBALL" | shasum -a 256 -c - >/dev/null \
  || { rm -f "$WORK/$TARBALL"; die "$WORK/$TARBALL doesn't match the pinned SHA-256 (removed; run again to download it anew)"; }

for ARCH in arm64 x86_64; do
  case $ARCH in
    arm64) HOST=aarch64-apple-darwin ;;
    x86_64) HOST=x86_64-apple-darwin ;;
  esac

  echo "→ Building aria2c $VERSION for $ARCH"
  SRC="$WORK/$ARCH/aria2-$VERSION"
  rm -rf "$WORK/$ARCH"
  mkdir -p "$WORK/$ARCH"
  tar -xf "$WORK/$TARBALL" -C "$WORK/$ARCH"

  FLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -O2"
  (
    cd "$SRC"
    # pkg-config off: configure then finds the SDK's libz by itself, the same on every Mac.
    ./configure --host="$HOST" \
      --disable-nls --disable-bittorrent --disable-metalink --disable-websocket \
      --with-appletls --without-gnutls --without-openssl --without-libnettle --without-libgmp --without-libgcrypt \
      --without-libxml2 --without-libexpat --without-libcares --without-libssh2 --without-sqlite3 \
      --with-libz PKG_CONFIG=/usr/bin/false \
      CC="$(xcrun -f clang)" CXX="$(xcrun -f clang++)" \
      CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS" \
      > ../configure.log 2>&1 || { tail -30 ../configure.log; exit 1; }
    make -j"$(sysctl -n hw.ncpu)" > ../make.log 2>&1 || { grep -E "error" ../make.log | head -20; exit 1; }
  ) || die "building for $ARCH failed (logs in $WORK/$ARCH)"

  BIN="$OUT/aria2c-$ARCH"
  cp "$SRC/src/aria2c" "$BIN"
  strip -x "$BIN"
  # Ad hoc, like the app: an arm64 binary must carry a signature to run at all.
  codesign --force --sign - "$BIN"

  [ "$(lipo -archs "$BIN")" = "$ARCH" ] || die "$BIN isn't $ARCH"
  # Only the system's own libraries.
  if otool -L "$BIN" | tail -n +2 | grep -vqE '^\s+(/usr/lib/|/System/Library/)'; then
    otool -L "$BIN"
    die "$BIN links a library outside macOS"
  fi
  echo "  $BIN: $(shasum -a 256 "$BIN" | cut -d' ' -f1)"
done

echo "Done. Update the SHA-256 sums in THIRD_PARTY_NOTICES.md if they changed."
