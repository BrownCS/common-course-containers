#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if ! grep -q '/usr/local/share/ccc/course_installer.sh' "$repo_root/share/open.sh"; then
  echo "FAIL: open flow does not use a fixed installer path" >&2
  exit 2
fi

if ! grep -q '/usr/local/share/ccc/course_installer.sh' "$repo_root/share/Dockerfile.template"; then
  echo "FAIL: Dockerfile template does not install the installer to a fixed path" >&2
  exit 2
fi

echo "PASS: fixed installer path is wired in"
