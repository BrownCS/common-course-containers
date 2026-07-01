#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/lib/config.sh"
. "$repo_root/lib/open.sh"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
mkdir -p "$CCC_COURSES_DIR" "$(resolve_config_dir)"

printf '{"course":"default","container_id":"abc123","pid":"","start":"now"}\n' > "$(resolve_config_dir)/session.json"

# Provide only the minimal command set needed for the scripts and ensure podman is not found.
TMP_BIN="$TMP_HOME/bin"
mkdir -p "$TMP_BIN"
for cmd in awk basename cat chmod date dirname grep head mkdir mv pwd rm sed sh uname; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ln -s "$(command -v "$cmd")" "$TMP_BIN/$cmd"
  fi
done
PATH="$TMP_BIN" ccc_close >/tmp/ccc-close-out 2>/tmp/ccc-close-err || status=$?
status=${status:-0}

if [ "$status" -ne 0 ]; then
  echo "FAIL: ccc_close exited with status $status" >&2
  echo "stdout:" >&2
  cat /tmp/ccc-close-out >&2
  echo "stderr:" >&2
  cat /tmp/ccc-close-err >&2
  exit 2
fi

if [ -f "$(resolve_config_dir)/session.json" ]; then
  echo "FAIL: session file was not cleared" >&2
  cat "$(resolve_config_dir)/session.json" >&2
  exit 2
fi

echo "PASS: ccc_close clears the session even when podman is unavailable"
