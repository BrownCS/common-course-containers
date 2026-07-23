#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/home"
cat >"$tmpdir/bin/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  -u) echo 20 ;;
  -g) echo 20 ;;
  -un) echo alice ;;
  -gn) echo staff ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmpdir/bin/id"

cat >"$tmpdir/bin/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TMPDIR/podman.log"
case "$1 $2" in
  "container exists") exit 1 ;;
  "network inspect") exit 1 ;;
  "network create") exit 0 ;;
  "image exists") exit 0 ;;
  "run --rm")
    printf 'root:x:0:0:root:/root:/bin/bash\n'
    printf 'dialout:x:20:20:dialout:/var/run/dialout:/usr/sbin/nologin\n'
    exit 0
    ;;
  "run")
    echo "FAIL: final container start should not run after identity conflict" >&2
    exit 1
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$tmpdir/bin/podman"

export TMPDIR="$tmpdir"
export PATH="$tmpdir/bin:$PATH"
export HOME="$tmpdir/home"
export CONTAINER_RUNTIME="podman"
export NETWORK_NAME="net-ccc"
export CONTAINER_NAME="ccc-test"
export PLATFORM="linux/amd64"
export IMAGE_NAME="ccc"
export CONTAINER_WORKDIR="/courses/course"

# shellcheck disable=SC1091
source "$repo_root/share/utils.sh"
# shellcheck disable=SC1091
source "$repo_root/share/container_helpers.sh"

set +e
start_new_container >"$tmpdir/out.log" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  cat "$tmpdir/out.log" >&2
  echo "FAIL: startup succeeded despite a uid/gid collision" >&2
  exit 1
fi

if ! grep -q 'Host uid/gid conflict with numeric accounts in image' "$tmpdir/out.log"; then
  cat "$tmpdir/out.log" >&2
  echo "FAIL: startup did not report the uid/gid conflict" >&2
  exit 1
fi

if grep -q '^run --detach' "$TMPDIR/podman.log"; then
  cat "$TMPDIR/podman.log" >&2
  echo "FAIL: final container run was attempted after a conflict" >&2
  exit 1
fi

echo "PASS: container startup fails fast on uid/gid conflicts"