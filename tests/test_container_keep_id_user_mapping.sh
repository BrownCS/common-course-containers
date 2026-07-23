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
  -u) echo 65001 ;;
  -g) echo 65002 ;;
  -un) echo alice ;;
  -gn) echo students ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmpdir/bin/id"

cat >"$tmpdir/bin/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TMPDIR/podman.log"
if [ "$1" = "container" ] && [ "$2" = "exists" ]; then
  exit 1
fi
if [ "$1" = "network" ] && [ "$2" = "inspect" ]; then
  exit 1
fi
if [ "$1" = "network" ] && [ "$2" = "create" ]; then
  exit 0
fi
if [ "$1" = "run" ]; then
  exit 0
fi
exit 0
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

if [ "$rc" -ne 0 ]; then
  cat "$tmpdir/out.log" >&2
  echo "FAIL: start_new_container returned $rc" >&2
  exit 1
fi

if ! grep -q -- "--userns keep-id:uid=65001,gid=65002" "$TMPDIR/podman.log"; then
  cat "$TMPDIR/podman.log" >&2
  echo "FAIL: container startup did not use keep-id userns mapping" >&2
  exit 1
fi

if ! grep -q -- "--passwd-entry alice::65001:65002:Default User:/home/alice:/bin/bash" "$TMPDIR/podman.log"; then
  cat "$TMPDIR/podman.log" >&2
  echo "FAIL: container startup did not inject the expected passwd entry" >&2
  exit 1
fi

if ! grep -q -- "--group-entry students::65002:alice" "$TMPDIR/podman.log"; then
  cat "$TMPDIR/podman.log" >&2
  echo "FAIL: container startup did not inject the expected group entry" >&2
  exit 1
fi

if grep -q -- "--user 0:0" "$TMPDIR/podman.log"; then
  cat "$TMPDIR/podman.log" >&2
  echo "FAIL: container startup still falls back to root" >&2
  exit 1
fi

echo "PASS: container startup keeps the host user identity inside the container"