#!/usr/bin/env bash
# Builds native/build/<config>/FromScratch.app. Usage: build-app.sh [debug|release]
set -euo pipefail

config="${1:-debug}"
case "$config" in
    debug | release) ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"

swift build -c "$config" --arch arm64
bin_dir="$(swift build -c "$config" --arch arm64 --show-bin-path)"

app="$root/build/$config/FromScratch.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin_dir/FromScratch" "$app/Contents/MacOS/FromScratch"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/FiraCode-Retina.otf" "$app/Contents/Resources/FiraCode-Retina.otf"
cp "$root/Resources/icon.icns" "$app/Contents/Resources/icon.icns"
printf 'APPL????' > "$app/Contents/PkgInfo"

codesign --force --sign - --timestamp=none "$app"
echo "Built $app"
