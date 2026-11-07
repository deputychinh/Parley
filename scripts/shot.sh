#!/bin/bash
# Screenshot of one screen with seeded sample data (never the user's ~/Documents/Parley).
# Usage: scripts/shot.sh <route> <name> [extra app args…]   e.g. scripts/shot.sh progress progress
#   SHOT_SIZE=720,820  window size (default 1200,740 — set every time so earlier runs can't leak a size)
#   SHOT_SEED=0        start from an empty data folder (empty states)
#   SHOT_DELAY=3       seconds to wait before capturing
# The sample folder lives under $TMPDIR (cleaned by macOS); nothing is deleted here. Only the instance this script
# starts is ever stopped — matched by its unique data folder, also on errors and timeouts — never the owner's Parley.
# Window/route state restoration is off for the shot instance (-ApplePersistenceIgnoreState YES).
set -euo pipefail
cd "$(dirname "$0")/.."
ROUTE=${1:?route}; NAME=${2:?name}; shift 2
DATA=$(mktemp -d "${TMPDIR:-/tmp}/parley-shot.XXXXXX")
[ "${SHOT_SEED:-1}" = 0 ] || .build/release/Parley --seed "$DATA"
WID=.build/window-id-v2   # v2 takes a PID
[ -x "$WID" ] || xcrun swiftc -O scripts/window-id.swift -o "$WID"

MATCH="MacOS/Parley --data-dir $DATA"
cleanup() { pkill -f -- "$MATCH" 2>/dev/null || true; }   # every instance started with our unique folder
trap cleanup EXIT

scripts/sandbox-app.sh >/dev/null   # own bundle id: window frames etc. never reach the owner's settings
open -n -a "$PWD/build/Parley-sandbox.app" --args --data-dir "$DATA" -ApplePersistenceIgnoreState YES \
  --route "$ROUTE" --window-size "${SHOT_SIZE:-1200,740}" "$@"
PID=""
for _ in $(seq 1 40); do
  PID=$(pgrep -f -- "$MATCH" | head -1 || true)
  [ -n "$PID" ] && break
  sleep 0.25
done
[ -n "$PID" ] || { echo "Parley did not start"; exit 1; }
ID=""
for _ in $(seq 1 40); do
  ID=$("$WID" "$PID" 2>/dev/null || true)
  [ -n "$ID" ] && break
  sleep 0.25
done
[ -n "$ID" ] || { echo "Parley window not found"; exit 1; }
sleep "${SHOT_DELAY:-2}"
ID=$("$WID" "$PID" 2>/dev/null || echo "$ID")   # the window may have changed meanwhile (e.g. --settings)
mkdir -p docs/screenshots
screencapture -o -x -l "$ID" "docs/screenshots/$NAME.png"
echo "docs/screenshots/$NAME.png (data: $DATA)"
