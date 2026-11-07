#!/bin/bash
# Smoke test for shot.sh: a decoy Parley (stand-in for the owner's) must survive, and no shot instance may remain.
set -euo pipefail
cd "$(dirname "$0")/.."
DECOY=$(mktemp -d "${TMPDIR:-/tmp}/parley-decoy.XXXXXX")
open -n -a "$PWD/build/Parley.app" --args --data-dir "$DECOY" -ApplePersistenceIgnoreState YES
trap 'pkill -f -- "MacOS/Parley --data-dir $DECOY" 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do pgrep -f -- "--data-dir $DECOY" >/dev/null && break; sleep 0.25; done
scripts/shot.sh progress _shot-test >/dev/null
sleep 1
pgrep -f -- "MacOS/Parley --data-dir $DECOY" >/dev/null || { echo "FAIL: shot.sh stopped another Parley"; exit 1; }
if pgrep -f -- "parley-shot\." >/dev/null; then echo "FAIL: a shot instance is still running"; exit 1; fi
[ -s docs/screenshots/_shot-test.png ] || { echo "FAIL: no screenshot"; exit 1; }
mv docs/screenshots/_shot-test.png "${TMPDIR:-/tmp}/"
echo "shot-test: ok (decoy alive, no leftover instance)"
