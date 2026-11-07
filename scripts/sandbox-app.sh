#!/bin/bash
# build/Parley-sandbox.app: a copy of build/Parley.app with its own bundle id (com.david.parley.sandbox), so anything
# macOS saves for a screenshot/review instance (window frames, state) lands in that app's domain — never the owner's.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Parley.app ] || { echo "build/Parley.app missing — run make app"; exit 1; }
if [ -d build/Parley-sandbox.app ] && [ build/Parley-sandbox.app/Contents/MacOS/Parley -nt build/Parley.app/Contents/MacOS/Parley ]; then
  exit 0
fi
rm -rf build/Parley-sandbox.app
ditto build/Parley.app build/Parley-sandbox.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.david.parley.sandbox" build/Parley-sandbox.app/Contents/Info.plist
touch build/Parley-sandbox.app/Contents/MacOS/Parley
codesign --force -s - build/Parley-sandbox.app >/dev/null 2>&1
echo "Built build/Parley-sandbox.app"
