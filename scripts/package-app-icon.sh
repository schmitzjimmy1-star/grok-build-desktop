#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: package-app-icon.sh ROOT_DIR BUILD_DIR APP_BUNDLE" >&2
    exit 64
fi

ROOT_DIR="$1"
BUILD_DIR="$2"
APP_BUNDLE="$3"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
OUTPUT="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

mkdir -p "$BUILD_DIR" "$APP_BUNDLE/Contents/Resources"

if [ -f "$ROOT_DIR/AppIcon.svg" ] && [ -f "$ROOT_DIR/scripts/render-app-icon.swift" ]; then
    SOURCE="$BUILD_DIR/AppIcon-master.png"
    echo "==> Rendering AppIcon.png from vector master"
    swift "$ROOT_DIR/scripts/render-app-icon.swift" "$ROOT_DIR/AppIcon.svg" "$SOURCE"
elif [ -f "$ROOT_DIR/AppIcon.png" ]; then
    SOURCE="$ROOT_DIR/AppIcon.png"
elif [ -f "$ROOT_DIR/AppIcon1024.png" ]; then
    SOURCE="$ROOT_DIR/AppIcon1024.png"
else
    echo "ERROR: Missing AppIcon.svg or 1024px PNG fallback" >&2
    exit 66
fi

echo "==> Generating AppIcon.icns from $SOURCE"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16     "$SOURCE" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
sips -z 64 64     "$SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$SOURCE" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT" >/dev/null
test -s "$OUTPUT"
rm -rf "$ICONSET_DIR"
