#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dockerfile="$repo_root/share/Dockerfile.template"

if grep -q 'direnv' "$dockerfile"; then
  echo "FAIL: Dockerfile still references direnv" >&2
  exit 1
fi

if ! grep -q 'chmod -R a+rX /usr/local/share/ccc' "$dockerfile"; then
  echo "FAIL: Dockerfile does not make copied CCC files readable/executable" >&2
  exit 1
fi

echo "PASS: container image no longer enables direnv and shares CCC files with read/execute permissions"
