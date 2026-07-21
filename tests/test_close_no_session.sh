#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"
. "$repo_root/share/open.sh"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
mkdir -p "$CCC_COURSES_DIR" "$(resolve_config_dir)"

if ! ccc_cleanup_environment "shell-exit" 0; then
  echo "FAIL: cleanup should exit successfully when no session exists" >&2
  exit 2
fi

if [ "${CCC_MANAGED_ENV:-}" != "false" ]; then
  echo "FAIL: cleanup did not clear the managed-environment marker" >&2
  exit 2
fi

echo "PASS: shell-exit cleanup works without an active session"
