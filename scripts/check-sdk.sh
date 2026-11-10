#!/bin/bash
# Fails when a built binary records an SDK version other than the one it was built with (see link-flags.sh):
# such a binary makes Translation miss installed packs on newer macOS.
set -euo pipefail
binary="$1"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk=$(xcrun --sdk macosx --show-sdk-version)
recorded=$(otool -l "$binary" | awk '/LC_BUILD_VERSION/ { f = 1 } f && / sdk / { print $2; exit }')
if [ "$recorded" != "$sdk" ]; then
  echo "$binary records SDK ${recorded:-none}, expected $sdk (scripts/link-flags.sh) — Translation would miss packs" >&2
  exit 1
fi
