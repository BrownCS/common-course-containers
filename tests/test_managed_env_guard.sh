#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
open_file="$repo_root/share/open.sh"

if ! grep -q 'is_managed_environment' "$open_file"; then
  echo "FAIL: open flow does not compute a managed-environment guard" >&2
  exit 2
fi

if grep -q 'CCC_ENV_MARKER_FILE\|CCC_CONTAINER_MARKER_FILE' "$open_file"; then
  echo "FAIL: managed-environment guard should rely on CCC_MANAGED_ENV rather than marker files" >&2
  exit 2
fi

if ! grep -q 'export CCC_MANAGED_ENV=true' "$open_file"; then
  echo "FAIL: open flow does not mark the course environment as managed on entry" >&2
  exit 2
fi

if ! grep -q 'export CCC_MANAGED_ENV=false' "$open_file"; then
  echo "FAIL: open flow does not clear the managed flag on host-side exit" >&2
  exit 2
fi

if ! grep -q 'You are already inside another CCC-managed course environment' "$open_file"; then
  echo "FAIL: open flow does not emit the managed-environment guard message" >&2
  exit 2
fi

echo "PASS: managed-environment guard is wired in"
