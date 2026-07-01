#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="localhost/ccc:latest"

if ! podman image exists "$image" >/dev/null 2>&1; then
  echo "FAIL: image $image not found" >&2
  exit 2
fi

output=$(podman run --rm --entrypoint /bin/bash "$image" -lc 'export PATH=/usr/local/bin:$PATH; ccc open default --no-shell' 2>&1)
status=$?

if [ "$status" -ne 0 ]; then
  echo "FAIL: ccc open inside container exited with status $status" >&2
  echo "$output" >&2
  exit 2
fi

if printf '%s
' "$output" | grep -q 'Please install podman'; then
  echo "FAIL: ccc open inside container still tried to require podman" >&2
  echo "$output" >&2
  exit 2
fi

if printf '%s
' "$output" | grep -q 'unbound variable'; then
  echo "FAIL: ccc open inside container still hit the unbound-variable path" >&2
  echo "$output" >&2
  exit 2
fi

echo "PASS: ccc open works inside the container without requiring podman"
