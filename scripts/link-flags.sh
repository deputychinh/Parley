#!/bin/bash
# SwiftPM records the deployment target (26.0) as the binary's SDK version. macOS 27 then treats Parley as an
# SDK-26 app, and Translation reports some installed packs (Japanese → English/Vietnamese) as not installed
# (`TranslationError.notInstalled`). Record the real SDK version; the minimum OS stays 26.0 (Package.swift).
set -euo pipefail
sdk=$(xcrun --sdk macosx --show-sdk-version)
echo "-Xlinker -platform_version -Xlinker macos -Xlinker 26.0 -Xlinker $sdk"
