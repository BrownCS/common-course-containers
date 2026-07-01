#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
open_file="$repo_root/lib/open.sh"
installer_file="$repo_root/lib/course_installer.sh"

if ! grep -q 'export CCC_MANAGED_ENV=true' "$open_file"; then
  echo "FAIL: open flow does not set CCC_MANAGED_ENV=true on entry" >&2
  exit 2
fi

if ! grep -q 'export CCC_MANAGED_ENV=false' "$open_file"; then
  echo "FAIL: open flow does not clear CCC_MANAGED_ENV=false on host-side exit" >&2
  exit 2
fi

if ! grep -q '.ccc-installer-ran' "$open_file" && ! grep -q 'installer-ran' "$open_file"; then
  echo "FAIL: open flow does not use an installer cache marker" >&2
  exit 2
fi

if ! grep -q '.ccc-installer-ran' "$installer_file"; then
  echo "FAIL: installer does not record that setup has already run" >&2
  exit 2
fi

echo "PASS: managed-env marker and installer cache markers are wired in"
