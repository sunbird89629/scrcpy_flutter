#!/usr/bin/env bash
# Reset a connected Android device to home, run a scrcpy_mcp real-device test,
# and print the agent's action sequence plus the result.
#
# Usage: run-e2e.sh [test-file] [device-serial]
#   test-file     defaults to the open-twitter agent e2e
#   device-serial defaults to the first connected device
set -uo pipefail

TEST="${1:-test/phone_agent_test/phone_agent_test_real.dart}"
DEV="${2:-$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"
[ -n "$DEV" ] || { echo "No Android device connected (adb devices)"; exit 1; }

ROOT="$(git rev-parse --show-toplevel)"
echo "Device:  $DEV"
echo "Test:    $TEST"
echo "Resetting to home..."
adb -s "$DEV" shell input keyevent KEYCODE_HOME >/dev/null 2>&1
sleep 1

LOG="$(mktemp -t verify-on-device)"
( cd "$ROOT/scrcpy_mcp" && dart test "$TEST" --tags real-device ) >"$LOG" 2>&1
echo "exit=$?"

echo "--- model actions (deduped) ---"
grep -oaE 'do\(action=\\"[A-Za-z ]+\\"(, (element|app|text|start|end|duration)=(\[[0-9][^]]*\]|\\"[^\\]*\\"))*\)|finish\(message=\\"[^\\]{0,40}' "$LOG" \
  | grep -avE 'xxx|x,y|x1,y1|x seconds|=\[x' | awk '!seen[$0]++'

echo "--- result ---"
grep -aE "All tests passed|Some tests failed|Expected:|Actual:|reason:" "$LOG" \
  | grep -avE '"text"|xml version' | tail -6

echo "(full log: $LOG)"
