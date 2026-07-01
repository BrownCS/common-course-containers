#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/home"
cat >"$tmpdir/bin/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "container" ] && [ "$2" = "exists" ]; then
  exit 1
fi
if [ "$1" = "network" ] && [ "$2" = "inspect" ]; then
  exit 0
fi
if [ "$1" = "network" ] && [ "$2" = "create" ]; then
  exit 0
fi
if [ "$1" = "run" ]; then
  exit 0
fi
if [ "$1" = "inspect" ]; then
  echo "running"
  exit 0
fi
exit 0
EOF
chmod +x "$tmpdir/bin/podman"

cat >"$tmpdir/bin/xhost" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmpdir/bin/xhost"

export PATH="$tmpdir/bin:$PATH"
export HOME="$tmpdir/home"
export CCC_COURSES_DIR="$tmpdir/courses"
export CONTAINER_RUNTIME="podman"
export NETWORK_NAME="net-ccc"
export CONTAINER_NAME="ccc-test"
export PLATFORM="linux/amd64"
export IMAGE_NAME="ccc"
export CONTAINER_WORKDIR="/courses/course"

# shellcheck disable=SC1091
source "$repo_root/lib/utils.sh"
# shellcheck disable=SC1091
source "$repo_root/lib/container_helpers.sh"

set +e
start_new_container >"$tmpdir/out.log" 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  cat "$tmpdir/out.log" >&2
  echo "FAIL: start_new_container returned $rc" >&2
  exit 1
fi

if ! grep -q -- "--volume $CCC_COURSES_DIR:/courses" "$tmpdir/out.log"; then
  cat "$tmpdir/out.log" >&2
  echo "FAIL: container startup did not mount the courses directory" >&2
  exit 1
fi

echo "PASS: container startup uses a defined volume path"
