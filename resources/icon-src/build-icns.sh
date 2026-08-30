#!/bin/sh
# Regenerate resources/icon.icns and resources/icon.png from the SVG sources.
#
# Requires rsvg-convert (brew install librsvg); iconutil ships with macOS.
#
# Small sizes deliberately use different artwork. Below ~64px the scribbled
# strokes are under half a pixel wide and #829696 blends into the background,
# so 16px and 32px get the simplified three-bar version in a lighter ink. This
# is the same approach Apple's own icons take; the caret only appears at 64px
# and above.

set -eu
cd "$(dirname "$0")"

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert not found -- brew install librsvg" >&2
  exit 1
}

CHOSEN=$(sed -n 's/^CHOSEN = "\([a-z]*\)".*/\1/p' gen_icon.py)
DETAIL="variant-$CHOSEN.svg"
SMALL="variant-$CHOSEN-small.svg"

python3 gen_icon.py

SET=FromScratch.iconset
rm -rf "./$SET"
mkdir -p "./$SET"

r () { rsvg-convert -w "$2" -h "$2" "$1" -o "$SET/$3"; }
r "$SMALL"   16 icon_16x16.png
r "$SMALL"   32 icon_16x16@2x.png
r "$SMALL"   32 icon_32x32.png
r "$DETAIL"  64 icon_32x32@2x.png
r "$DETAIL" 128 icon_128x128.png
r "$DETAIL" 256 icon_128x128@2x.png
r "$DETAIL" 256 icon_256x256.png
r "$DETAIL" 512 icon_256x256@2x.png
r "$DETAIL" 512 icon_512x512.png
r "$DETAIL" 1024 icon_512x512@2x.png

iconutil -c icns "./$SET" -o ../icon.icns
rsvg-convert -w 1024 -h 1024 "$DETAIL" -o ../icon.png
rm -rf "./$SET"

echo "wrote ../icon.icns and ../icon.png"
