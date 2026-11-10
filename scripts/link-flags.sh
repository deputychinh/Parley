#!/bin/bash
# SwiftPM records the deployment target (26.0) as the binary's SDK version. macOS 27 then treats Parley as an
# SDK-26 app, and Translation reports some installed packs (Japanese → English/Vietnamese) as not installed
# (`TranslationError.notInstalled`). Record the real SDK version; the minimum OS comes from Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" # same Xcode as the build
minos=$(sed -nE 's/.*\.macOS\("([0-9.]+)"\).*/\1/p' Package.swift)
[ -n "$minos" ] || { echo "link-flags: no .macOS(\"x\") platform in Package.swift" >&2; exit 1; }
sdk=$(xcrun --sdk macosx --show-sdk-version)
echo "-Xlinker -platform_version -Xlinker macos -Xlinker $minos -Xlinker $sdk"
