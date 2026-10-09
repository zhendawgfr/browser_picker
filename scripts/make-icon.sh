#!/bin/bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns. Needs resvg (brew install resvg).
# Run only after changing the SVG; the .icns is committed so building the app does not need resvg.
set -euo pipefail

cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
ICNS="Resources/AppIcon.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    resvg -w "$size" -h "$size" "$SVG" "$ICONSET/icon_${size}x${size}.png"
    resvg -w "$((size * 2))" -h "$((size * 2))" "$SVG" "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$(dirname "$ICONSET")"
echo "Wrote $ICNS"
