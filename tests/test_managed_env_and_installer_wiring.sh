#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
open_file="$repo_root/share/open.sh"
installer_file="$repo_root/share/course_installer.sh"

if ! grep -q 'export CCC_MANAGED_ENV=true' "$open_file"; then
  echo "FAIL: open flow does not set CCC_MANAGED_ENV=true on entry" >&2
  exit 2
fi

if ! grep -q 'export CCC_MANAGED_ENV=false' "$open_file"; then
  echo "FAIL: open flow does not clear CCC_MANAGED_ENV=false on host-side exit" >&2
  exit 2
fi

if ! grep -q 'package_is_installed' "$installer_file"; then
  echo "FAIL: installer does not check package installation status directly" >&2
  exit 2
fi

if ! grep -q 'PACKAGES_FILE' "$installer_file" || ! grep -q 'LINKS_FILE' "$installer_file" || ! grep -q 'ENV_FILE' "$installer_file"; then
  echo "FAIL: installer does not read the manifest files directly" >&2
  exit 2
fi

echo "PASS: managed-env marker and manifest-driven installer wiring are present"