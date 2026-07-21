#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"
. "$repo_root/share/utils.sh"
. "$repo_root/share/open.sh"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
mkdir -p "$CCC_COURSES_DIR" "$(resolve_config_dir)"
export CCC_MANAGED_ENV=true

ccc_cleanup_environment "shell-exit" 0

if [ "${CCC_MANAGED_ENV:-}" != "false" ]; then
  echo "FAIL: cleanup did not switch CCC_MANAGED_ENV to false" >&2
  exit 2
fi

echo "PASS: cleanup disables the managed-env marker"
