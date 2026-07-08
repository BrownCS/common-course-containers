#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/home" "$tmpdir/courses"
export HOME="$tmpdir/home"
export CCC_COURSES_DIR="$tmpdir/courses"
export REGISTRY_FILE="$repo_root/registry.csv"

cat >"$tmpdir/bin/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TMPDIR/podman.log"
exit 0
EOF
chmod +x "$tmpdir/bin/podman"

export TMPDIR="$tmpdir"
export PATH="$tmpdir/bin:$PATH"

# shellcheck disable=SC1091
source "$repo_root/share/config.sh"
# shellcheck disable=SC1091
source "$repo_root/share/utils.sh"
# shellcheck disable=SC1091
source "$repo_root/share/courses.sh"
# shellcheck disable=SC1091
source "$repo_root/share/container_helpers.sh"
# shellcheck disable=SC1091
source "$repo_root/share/runtime.sh"
# shellcheck disable=SC1091
source "$repo_root/share/open.sh"

ensure_course_exists() { return 0; }
ccd_clone_if_missing() { return 0; }
get_course_requires_container() { echo true; }
build_image() { return 0; }
start_new_container() { return 0; }
detect_container_runtime() { echo podman; }

mkdir -p "$(resolve_config_dir)"

set +e
ccc_open csci-0300-demo >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo "FAIL: ccc_open returned $rc" >&2
  exit 1
fi

if ! grep -q "default" "$TMPDIR/podman.log"; then
  echo "FAIL: open did not attach to the shared default container" >&2
  cat "$TMPDIR/podman.log" >&2
  exit 1
fi

if ! grep -q "/courses/csci-0300-demo/env/course.env" "$TMPDIR/podman.log"; then
  echo "FAIL: open did not source the course env file in the shell command" >&2
  cat "$TMPDIR/podman.log" >&2
  exit 1
fi

echo "PASS: open reuses the shared default container and sources course env"