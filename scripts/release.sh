#!/bin/bash
# make release-zip VERSION=0.4.0 → dist/Parley-<version>-macOS-arm64.zip + .sha256, ready for a GitHub release.
# Ad-hoc signed (no local certificate in a public file); not notarized — README explains "Open Anyway".
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release.sh <version, e.g. 0.4.0>}
SHORT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
[ "$SHORT" = "$VERSION" ] || { echo "Info.plist says $SHORT, not $VERSION — bump CFBundleShortVersionString first"; exit 1; }
PARLEY_SIGN=- ./build.sh
codesign --verify --deep --strict build/Parley.app
[ "$(lipo -archs build/Parley.app/Contents/MacOS/Parley)" = "arm64" ] || { echo "expected an arm64 binary"; exit 1; }
mkdir -p dist
ZIP="Parley-$VERSION-macOS-arm64.zip"
rm -f "dist/$ZIP" "dist/$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent build/Parley.app "dist/$ZIP"
(cd dist && shasum -a 256 "$ZIP" > "$ZIP.sha256")
cat "dist/$ZIP.sha256"
echo "dist/$ZIP ($(du -h "dist/$ZIP" | cut -f1))"
