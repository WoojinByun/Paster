#!/bin/bash
# Resources/AppIcon.svg 를 Resources/AppIcon.icns 로 만든다. 결과물은 커밋되므로 아이콘을 바꿀 때만 실행한다.
set -euo pipefail
cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
ICNS="Resources/AppIcon.icns"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/png" "$WORK/AppIcon.iconset"

swift scripts/render-icon.swift "$SVG" "$WORK/png" 16 32 64 128 256 512 1024

ICONSET="$WORK/AppIcon.iconset"
for size in 16 32 128 256 512; do
    cp "$WORK/png/$size.png" "$ICONSET/icon_${size}x${size}.png"
    cp "$WORK/png/$((size * 2)).png" "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"
mv "$WORK/AppIcon.icns" "$ICNS"
echo "$ICNS"
