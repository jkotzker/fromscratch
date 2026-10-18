#!/bin/sh
# Regenerate resources/icon.icns, icon.png and icon.ico from the SVG sources.
#
# Requires rsvg-convert (brew install librsvg) and magick (brew install
# imagemagick); iconutil ships with macOS.
#
# Small sizes deliberately use different artwork. At 16px a 50-unit bar is
# 0.78px wide and the four rows blur into one smear, so 16px and 32px get the
# simplified three-bar version in a lighter ink. This is the same approach
# Apple's own icons take.

set -eu
cd "$(dirname "$0")"

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert not found -- brew install librsvg" >&2
  exit 1
}
command -v magick >/dev/null || {
  echo "magick not found -- brew install imagemagick" >&2
  exit 1
}

CHOSEN=$(sed -n 's/^CHOSEN = "\([a-z-]*\)".*/\1/p' gen_icon.py)
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

# Windows .ico. Built from the same sources so it cannot drift from the macOS
# icon the way the original upstream .ico had; the small sizes use the
# simplified artwork for the same reason the .icns does.
ICO=ico-tmp
rm -rf "./$ICO"
mkdir -p "./$ICO"
rsvg-convert -w 16  -h 16  "$SMALL"  -o "$ICO/16.png"
rsvg-convert -w 24  -h 24  "$SMALL"  -o "$ICO/24.png"
rsvg-convert -w 32  -h 32  "$SMALL"  -o "$ICO/32.png"
rsvg-convert -w 48  -h 48  "$DETAIL" -o "$ICO/48.png"
rsvg-convert -w 64  -h 64  "$DETAIL" -o "$ICO/64.png"
rsvg-convert -w 128 -h 128 "$DETAIL" -o "$ICO/128.png"
rsvg-convert -w 256 -h 256 "$DETAIL" -o "$ICO/256.png"
magick "$ICO/16.png" "$ICO/24.png" "$ICO/32.png" "$ICO/48.png" \
       "$ICO/64.png" "$ICO/128.png" "$ICO/256.png" ../icon.ico

rm -rf "./$SET" "./$ICO"

echo "wrote ../icon.icns, ../icon.png and ../icon.ico"
