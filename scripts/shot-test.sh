#!/bin/bash
# Smoke test for shot.sh: a decoy Parley (stand-in for the owner's) must survive, and no instance started by this
# run may remain. Other sessions' shot instances are ignored (only PIDs that appeared during this run count).
set -euo pipefail
cd "$(dirname "$0")/.."
DECOY=$(mktemp -d "${TMPDIR:-/tmp}/parley-decoy.XXXXXX")
PNG=docs/screenshots/_shot-test.png
trap 'pkill -f -- "MacOS/Parley --data-dir $DECOY" 2>/dev/null || true; mv -f "$PNG" "${TMPDIR:-/tmp}/" 2>/dev/null || true' EXIT
APP="MacOS/Parley( |$)"   # not MacOS/ParleyTests (a concurrent swift test)
BEFORE=$(pgrep -f -- "$APP" | sort || true)
open -n -a "$PWD/build/Parley.app" --args --data-dir "$DECOY" -ApplePersistenceIgnoreState YES
DECOY_PID=""
for _ in $(seq 1 40); do DECOY_PID=$(pgrep -f -- "MacOS/Parley --data-dir $DECOY" | head -1 || true); [ -n "$DECOY_PID" ] && break; sleep 0.25; done
[ -n "$DECOY_PID" ] || { echo "FAIL: the decoy did not start"; exit 1; }
scripts/shot.sh progress _shot-test >/dev/null
sleep 1
kill -0 "$DECOY_PID" 2>/dev/null || { echo "FAIL: shot.sh stopped another Parley"; exit 1; }
AFTER=$(pgrep -f -- "$APP" | sort || true)
LEFT=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep -vx "$DECOY_PID" || true)
[ -z "$LEFT" ] || { echo "FAIL: shot instance(s) still running: $LEFT"; exit 1; }
[ -s "$PNG" ] || { echo "FAIL: no screenshot"; exit 1; }
echo "shot-test: ok (decoy alive, no leftover instance)"
