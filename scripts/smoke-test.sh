#!/usr/bin/env bash
# Launches a built Marc.app with in-memory test storage and fails if it exits within a few
# seconds, catching launch-time problems such as frameworks that dyld refuses to load.
#
# Usage: scripts/smoke-test.sh path/to/Marc.app [seconds]
set -euo pipefail

app="${1:?usage: smoke-test.sh <Marc.app> [seconds]}"
seconds="${2:-15}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$app/Contents/MacOS/Marc" -ui-testing > "$log" 2>&1 &
pid=$!
sleep "$seconds"
if ! kill -0 "$pid" 2> /dev/null; then
  wait "$pid" || status=$?
  echo "error: Marc exited during launch (status ${status:-0}). Output:" >&2
  cat "$log" >&2
  exit 1
fi
kill "$pid"
wait "$pid" 2> /dev/null || true
echo "Marc launched and kept running for ${seconds}s."
