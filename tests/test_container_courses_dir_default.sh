#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if ! grep -q 'CCC_COURSES_DIR=.*\${HOME}/courses' "$repo_root/ccc.sh"; then
  echo "FAIL: ccc entrypoint does not provide a host-side default courses directory" >&2
  exit 2
fi

if ! grep -q 'CCC_COURSES_DIR=.*\/courses' "$repo_root/ccc.sh"; then
  echo "FAIL: ccc entrypoint does not provide a container-side default courses directory" >&2
  exit 2
fi

echo "PASS: ccc entrypoint defaults the courses directory for host and container" 
