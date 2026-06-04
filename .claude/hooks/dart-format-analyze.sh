#!/usr/bin/env bash
# PostToolUse hook: after an Edit/Write/MultiEdit to a .dart file, format it in
# place and analyze it with the project's strict lints. On analysis failure the
# issues are written to stderr with exit 2 so Claude sees and fixes them.
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' \
  2>/dev/null)"

case "$file" in
  *.dart) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Format the edited file (best effort; analyze reports any parse error).
dart format "$file" >/dev/null 2>&1

# Analyze just the edited file (fast) with the same strictness as `melos run analyze`.
out="$(dart analyze --fatal-infos --fatal-warnings "$file" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  { echo "dart analyze found issues in $file:"; echo "$out"; } >&2
  exit 2
fi
exit 0
