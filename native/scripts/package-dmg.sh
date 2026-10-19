#!/usr/bin/env bash
# Packages native/build/release/FromScratch.app into
# native/build/FromScratch-<version>-arm64.dmg. Run build-app.sh release first.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
app="$root/build/release/FromScratch.app"

if [[ ! -d "$app" ]]; then
    echo "missing $app; run native/scripts/build-app.sh release first" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="$root/build/FromScratch-$version-arm64.dmg"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# ditto, not tar: it keeps the bundle's symlinks, xattrs and ad-hoc signature intact.
ditto "$app" "$staging/FromScratch.app"
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
hdiutil create -volname FromScratch -srcfolder "$staging" -fs APFS -format ULFO "$dmg"

echo "$dmg"
