#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
open_file="$repo_root/lib/open.sh"

if grep -q 'echo "Installer not found; skipping automated setup"' "$open_file"; then
  echo "FAIL: open flow still falls back to a host-side skip message" >&2
  exit 2
fi

if ! grep -q 'bash -lc' "$open_file"; then
  echo "FAIL: installer execution is not routed through the container command" >&2
  exit 2
fi

echo "PASS: installer launch is delegated to the container runtime"
