#!/usr/bin/env sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_BIN="$(mktemp -d)"
TMP_LOG="$TMP_HOME/podman.log"
cleanup() {
  rm -rf "$TMP_HOME" "$TMP_BIN"
}
trap cleanup EXIT HUP INT TERM

cat >"$TMP_BIN/podman" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${TMP_PODMAN_LOG:?}"
case "$1 $2 $3" in
  "container exists"*) exit 0 ;;
  "image exists"*) exit 0 ;;
  "container stop"*) exit 0 ;;
  "container rm"*) exit 0 ;;
  "image rm"*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP_BIN/podman"

export PATH="$TMP_BIN:$PATH"
export TMP_PODMAN_LOG="$TMP_LOG"
export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"
export CCC_REGISTRY_FILE="$TMP_HOME/registry.csv"

. "$repo_root/share/config.sh"

mkdir -p "$CCC_COURSES_DIR/cleanup-course" "$(dirname "$TMP_PODMAN_LOG")"
mkdir -p "$TMP_HOME/registry-src"
cat >"$CCC_REGISTRY_FILE" <<'EOF'
cleanup-course,https://example.invalid/cleanup-course.git,Cleanup Course,now,true,course-specific,ghcr.io/example/cleanup-course:latest,,main,Test course for cleanup
EOF

course_dir="$CCC_COURSES_DIR/cleanup-course"
mkdir -p "$course_dir/setup" "$course_dir/env"
printf 'repo content\n' >"$course_dir/README.md"
: >"$course_dir/setup/install.log"
: >"$course_dir/env/course.env"
: >"$course_dir/.ccc-installer-ran"

session_dir="$(resolve_config_dir)"
mkdir -p "$session_dir"
printf '{"course":"cleanup-course","container_id":"ccc-cleanup-course","pid":"","start":"now"}\n' >"$session_dir/session.json"

bash "$repo_root/ccc.sh" cleanup cleanup-course >/dev/null 2>&1

if [ ! -f "$course_dir/README.md" ]; then
  echo "FAIL: cleanup removed course repo content" >&2
  exit 2
fi

for path in \
  "$course_dir/.ccc-installer-ran" \
  "$course_dir/setup/install.log" \
  "$course_dir/env/course.env" \
  "$session_dir/session.json"; do
  if [ -e "$path" ]; then
    echo "FAIL: cleanup left generated state behind: $path" >&2
    exit 2
  fi
done

if ! grep -q 'container exists ccc-cleanup-course' "$TMP_PODMAN_LOG"; then
  echo "FAIL: cleanup did not check for the course container" >&2
  exit 2
fi

if ! grep -q '^stop ccc-cleanup-course$' "$TMP_PODMAN_LOG"; then
  echo "FAIL: cleanup did not stop the course container" >&2
  exit 2
fi

if ! grep -q '^rm -f ccc-cleanup-course$' "$TMP_PODMAN_LOG"; then
  echo "FAIL: cleanup did not remove the course container" >&2
  exit 2
fi

if ! grep -q '^image exists ccc-cleanup-course$' "$TMP_PODMAN_LOG"; then
  echo "FAIL: cleanup did not check for the course image" >&2
  exit 2
fi

if ! grep -q '^image rm -f ccc-cleanup-course$' "$TMP_PODMAN_LOG"; then
  echo "FAIL: cleanup did not remove the course image" >&2
  exit 2
fi

echo "PASS: ccc cleanup removes course runtime state and preserves the repo"