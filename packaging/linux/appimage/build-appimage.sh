#!/usr/bin/env bash
#
# Packages an already-built Flutter Linux bundle as an AppImage.
#
#   flutter build linux --release
#   packaging/linux/appimage/build-appimage.sh
#
# Same input as the Flatpak manifest — build/linux/<arch>/release/bundle — for
# the same reason: `printing` downloads pdfium during the CMake configure step,
# so the bundle has to come out of a normal build on a machine with network.
# It already contains lib/libpdfium.so, so nothing is fetched here.
#
# WHAT THIS DELIBERATELY DOES NOT DO
#
# It does not run linuxdeploy and does not copy a single system library into the
# AppDir. A Flutter bundle is already self-contained for everything it owns
# (the engine, every plugin .so, pdfium) and is linked against the system GTK 3,
# GStreamer, libsecret and glibc on purpose. Bundling those would be worse, not
# better: a bundled GTK stops picking up the user's theme and cannot load the
# host's GIO/gdk-pixbuf modules, and a bundled GStreamer loses the codecs the
# distribution installed.
#
# The trade-off is that this AppImage is portable, not self-sufficient — unlike
# the Flatpak, which brings its own runtime, it assumes the host provides:
#
#   * glibc at least as new as the build machine's (build on the oldest
#     distribution you intend to support — CI uses ubuntu-22.04, glibc 2.35)
#   * GTK 3, and the GTK/GDK stack around it
#   * libsecret + a running secret service, or the app cannot keep a session
#   * gstreamer1.0-plugins-base/good/bad — voice playback
#   * zenity or kdialog — the attachment file picker
#   * pulseaudio-utils and ffmpeg — voice recording
#
# Every one of those is present on a normal desktop install; see docs/LINUX.md
# for what the user sees when one of them is missing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PACKAGING_DIR="$REPO_ROOT/packaging/linux"
APP_ID="com.ahmadre.hinata"

# Flutter names its output directory x64/arm64, the AppImage world uses the
# uname spelling. Both are needed: one to find the bundle, one to name the file
# and to tell appimagetool which runtime to embed.
case "$(uname -m)" in
  x86_64)  FLUTTER_ARCH=x64;   APPIMAGE_ARCH=x86_64  ;;
  aarch64) FLUTTER_ARCH=arm64; APPIMAGE_ARCH=aarch64 ;;
  *)
    echo "Unsupported architecture $(uname -m) — Flutter builds Linux for x64 and arm64." >&2
    exit 1
    ;;
esac

BUNDLE_DIR="$REPO_ROOT/build/linux/$FLUTTER_ARCH/release/bundle"
if [[ ! -x "$BUNDLE_DIR/hinata" ]]; then
  echo "No release bundle at $BUNDLE_DIR." >&2
  echo "Run 'flutter build linux --release' first." >&2
  exit 1
fi

# The version the AppImage is named after comes from pubspec.yaml, so the file
# name can never disagree with what the app reports about itself. `10.1.0+81`
# → `10.1.0`; the build number is not part of a user-facing file name.
VERSION="$(sed -n 's/^version: *\([^+]*\).*/\1/p' "$REPO_ROOT/pubspec.yaml" | head -n1)"
if [[ -z "$VERSION" ]]; then
  echo "Could not read 'version:' from pubspec.yaml." >&2
  exit 1
fi

OUT_DIR="$REPO_ROOT/build/linux/appimage"
APPDIR="$OUT_DIR/$APP_ID.AppDir"
TOOLS_DIR="$OUT_DIR/tools"
OUTPUT="$OUT_DIR/Hinata-$VERSION-$APPIMAGE_ARCH.AppImage"

# Only ever removes this script's own output directory, never anything the
# build produced or the user wrote.
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$TOOLS_DIR"

# The whole bundle goes into usr/bin, unsplit: the runner resolves
# data/flutter_assets and lib/ relative to its own executable, and the plugin
# libraries have an RPATH of $ORIGIN/lib. Separating the executable from its
# neighbours is the one way to break both at once.
cp -a "$BUNDLE_DIR/." "$APPDIR/usr/bin/"

install -Dm644 "$PACKAGING_DIR/$APP_ID.desktop" \
  "$APPDIR/usr/share/applications/$APP_ID.desktop"
install -Dm644 "$PACKAGING_DIR/$APP_ID.metainfo.xml" \
  "$APPDIR/usr/share/metainfo/$APP_ID.metainfo.xml"
install -Dm644 "$PACKAGING_DIR/icons/hicolor/512x512/apps/$APP_ID.png" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

# appimagetool insists on finding the desktop entry, the icon named by its Icon=
# key and .DirIcon at the AppDir ROOT, in addition to the copies under usr/share
# that a desktop integrator installs. Symlinks, so there is still only one file.
ln -sf "usr/share/applications/$APP_ID.desktop" "$APPDIR/$APP_ID.desktop"
ln -sf "usr/share/icons/hicolor/512x512/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
ln -sf "$APP_ID.png" "$APPDIR/.DirIcon"

# AppRun is what the mounted image executes. A symlink is enough because the
# binary needs no environment of its own — and because $ORIGIN and /proc/self/exe
# both resolve through the symlink to usr/bin, where the bundle actually lives.
ln -sf "usr/bin/hinata" "$APPDIR/AppRun"

APPIMAGETOOL="$TOOLS_DIR/appimagetool-$APPIMAGE_ARCH.AppImage"
if [[ ! -x "$APPIMAGETOOL" ]]; then
  echo "Fetching appimagetool for $APPIMAGE_ARCH…"
  curl -fSL --retry 3 -o "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$APPIMAGE_ARCH.AppImage"
  chmod +x "$APPIMAGETOOL"
fi

# --appimage-extract-and-run: appimagetool is itself an AppImage, and CI
# containers routinely have no FUSE. This makes it unpack itself instead of
# mounting, which is the difference between "works everywhere" and "works on a
# developer laptop".
ARCH="$APPIMAGE_ARCH" "$APPIMAGETOOL" --appimage-extract-and-run \
  "$APPDIR" "$OUTPUT"

echo "Wrote $OUTPUT"
