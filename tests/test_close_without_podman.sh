#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"
. "$repo_root/share/open.sh"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
mkdir -p "$CCC_COURSES_DIR" "$(resolve_config_dir)"

printf '{"course":"default","container_id":"abc123","pid":"","start":"now"}\n' > "$(resolve_config_dir)/session.json"

if ! ccc_cleanup_environment "shell-exit" 0; then
  echo "FAIL: shell-exit cleanup exited with an error" >&2
  exit 2
fi

if [ -f "$(resolve_config_dir)/session.json" ]; then
  echo "FAIL: session file was not cleared" >&2
  cat "$(resolve_config_dir)/session.json" >&2
  exit 2
fi

if [ "${CCC_MANAGED_ENV:-}" != "false" ]; then
  echo "FAIL: managed-environment marker was not reset" >&2
  exit 2
fi

echo "PASS: shell-exit cleanup clears the session and managed-env marker"
