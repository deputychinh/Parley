#!/bin/bash
# Builds build/<CFBundleName>.app. To rename the app, edit CFBundleName/CFBundleDisplayName in Info.plist only.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" # CLT lacks the macro plugins
NAME=$(/usr/libexec/PlistBuddy -c "Print CFBundleName" Info.plist)
EXE=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" Info.plist)
FLAGS=$(scripts/link-flags.sh) # own line, so `set -e` stops on failure
# shellcheck disable=SC2086 # word-splitting the flags is intended
swift build -c release -Xswiftc -warnings-as-errors $FLAGS
scripts/check-sdk.sh ".build/release/$EXE"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$EXE" "$APP/Contents/MacOS/"
cp Resources/* "$APP/Contents/Resources/"
# Icon Composer format so macOS 26+ renders it natively (no gray "legacy icon" frame). Glyph: scripts/make-icon.swift
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist .build/icon-partial.plist >/dev/null
cp Info.plist "$APP/Contents/"
# A stable identity keeps macOS privacy permissions across rebuilds; ad-hoc (-) loses them on every build.
ID="LiveTranslate Local Signing"
security find-identity -p codesigning | grep -q "$ID" || ID=-
codesign --force -s "$ID" "$APP"
echo "Signed with: $ID"
echo "Built $APP"

# ./build.sh install → replace /Applications/<name>.app and launch it (permissions survive: same bundle id + certificate).
if [ "${1:-}" = "install" ]; then
  BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Info.plist)
  osascript -e "quit app id \"$BID\"" 2>/dev/null || true
  sleep 1
  ditto "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed /Applications/$NAME.app"
fi
