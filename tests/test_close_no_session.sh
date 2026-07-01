#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/lib/config.sh"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
mkdir -p "$CCC_COURSES_DIR"

# Simulate no active session
rm -f "$(resolve_config_dir)/session.json"

output=$("$repo_root/ccc.sh" close 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  echo "FAIL: close should exit successfully when no session exists" >&2
  echo "$output" >&2
  exit 2
fi

if printf '%s
' "$output" | grep -q 'Nothing to close'; then
  echo "PASS: close reports nothing to close"
else
  echo "FAIL: close did not report nothing to close" >&2
  echo "$output" >&2
  exit 2
fi
