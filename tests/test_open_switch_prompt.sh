#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"
. "$repo_root/share/utils.sh"
. "$repo_root/share/open.sh"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
mkdir -p "$CCC_COURSES_DIR"
mkdir -p "$(resolve_config_dir)"

export CCC_MANAGED_ENV=true
ensure_course_exists() { return 0; }
ccd_clone_if_missing() { return 0; }
get_course_requires_container() { echo true; }
start_container_for_course() { return 0; }

set +e
output=$(ccc_open new-course --no-shell 2>&1)
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  echo "FAIL: open unexpectedly succeeded when managed-env is active" >&2
  echo "$output" >&2
  exit 2
fi

if ! printf '%s\n' "$output" | grep -q 'already inside another CCC-managed course environment'; then
  echo "FAIL: open did not block nested opens when managed-env is active" >&2
  echo "$output" >&2
  exit 2
fi

echo "PASS: open blocks nested opens when managed-env is active"
