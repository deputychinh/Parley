#!/bin/bash
# Screenshot of one screen with seeded sample data (never the user's ~/Documents/Parley).
# Usage: scripts/shot.sh <route> <name> [extra app args…]   e.g. scripts/shot.sh progress progress
# SHOT_SIZE=720,820 resizes the window first (narrow-layout check).
# The sample folder is created under $TMPDIR (cleaned by macOS); nothing is deleted here.
# Only the instance this script starts is ever stopped (by PID, also on error); the owner's Parley is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
ROUTE=${1:?route}; NAME=${2:?name}; shift 2
DATA=$(mktemp -d "${TMPDIR:-/tmp}/parley-shot.XXXXXX")
.build/release/Parley --seed "$DATA"
WID=.build/window-id-v2   # v2 takes a PID
[ -x "$WID" ] || xcrun swiftc -O scripts/window-id.swift -o "$WID"

PID=""
cleanup() { if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi; }
trap cleanup EXIT

open -n -a "$PWD/build/Parley.app" --args --data-dir "$DATA" --route "$ROUTE" ${SHOT_SIZE:+--window-size "$SHOT_SIZE"} "$@"
for _ in $(seq 1 40); do   # the temp folder is unique, so it identifies our instance
  PID=$(pgrep -f -- "MacOS/Parley --data-dir $DATA" | head -1 || true)
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
mkdir -p docs/screenshots
screencapture -o -x -l "$ID" "docs/screenshots/$NAME.png"
echo "docs/screenshots/$NAME.png (data: $DATA)"
