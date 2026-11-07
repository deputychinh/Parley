#!/bin/bash
# Screenshot of one screen with seeded sample data (never the user's ~/Documents/Parley).
# Usage: scripts/shot.sh <route> <name> [extra app args…]   e.g. scripts/shot.sh progress progress
# SHOT_SIZE=720,820 resizes the window first (narrow-layout check).
# The sample folder is created under $TMPDIR (cleaned by macOS); nothing is deleted here.
set -euo pipefail
cd "$(dirname "$0")/.."
ROUTE=${1:?route}; NAME=${2:?name}; shift 2
# Never stop the owner's own Parley (it may be recording a meeting).
if pgrep -x Parley >/dev/null; then echo "Parley is running — quit it first (a screenshot needs its own instance)."; exit 1; fi
DATA=$(mktemp -d "${TMPDIR:-/tmp}/parley-shot.XXXXXX")
.build/release/Parley --seed "$DATA"
open -n -a "$PWD/build/Parley.app" --args --data-dir "$DATA" --route "$ROUTE" ${SHOT_SIZE:+--window-size "$SHOT_SIZE"} "$@"
WID=.build/window-id
[ -x "$WID" ] || xcrun swiftc -O scripts/window-id.swift -o "$WID"
ID=""
for _ in $(seq 1 40); do
  ID=$("$WID" Parley 2>/dev/null || true)
  [ -n "$ID" ] && break
  sleep 0.25
done
[ -n "$ID" ] || { echo "Parley window not found"; exit 1; }
sleep "${SHOT_DELAY:-2}"
mkdir -p docs/screenshots
screencapture -o -x -l "$ID" "docs/screenshots/$NAME.png"
pkill -x Parley || true   # only the instance started above: none was running before
echo "docs/screenshots/$NAME.png (data: $DATA)"
