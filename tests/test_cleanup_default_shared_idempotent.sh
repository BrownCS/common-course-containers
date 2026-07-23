#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
trap 'rm -rf "$tmp_home" "$tmp_bin"' EXIT

mkdir -p "$tmp_home/courses/csci-0300-demo" "$tmp_home/courses/csci-1380-demo" "$tmp_home/courses/csci-1515-demo" "$tmp_home/cccreg"

cat >"$tmp_bin/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "container exists"|"image exists") exit 0 ;;
  "container stop"|"container rm"|"image rm") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$tmp_bin/podman"

export PATH="$tmp_bin:$PATH"
export HOME="$tmp_home"
export CCC_COURSES_DIR="$tmp_home/courses"
export CCC_REGISTRY_FILE="$tmp_home/registry.csv"

cat >"$CCC_REGISTRY_FILE" <<'EOF'
csci-0300-demo,https://example.invalid/csci-0300-demo.git,CSCI 0300 Demo,now,true,default,,,,
csci-1380-demo,https://example.invalid/csci-1380-demo.git,CSCI 1380 Demo,now,true,default,,,,
csci-1515-demo,https://example.invalid/csci-1515-demo.git,CSCI 1515 Demo,now,true,default,,,,
EOF

tracking_file="$tmp_home/.ccc/default-container-courses.txt"
mkdir -p "$(dirname "$tracking_file")"
printf 'csci-0300-demo\ncsci-1380-demo\ncsci-1515-demo\n' >"$tracking_file"

cleanup1_out="$tmp_home/cleanup1.out"
cleanup2_out="$tmp_home/cleanup2.out"

printf 'y\n' | script -qec "bash '$repo_root/bin/ccc' cleanup csci-0300-demo" /dev/null >"$cleanup1_out" 2>&1 || {
  cat "$cleanup1_out" >&2
  exit 1
}

if ! grep -q 'The shared default container is still used by:' "$cleanup1_out"; then
  cat "$cleanup1_out" >&2
  echo "FAIL: first cleanup did not show the shared default container warning" >&2
  exit 1
fi

if [ -f "$tracking_file" ] && grep -q '.' "$tracking_file"; then
  cat "$tracking_file" >&2
  echo "FAIL: first cleanup left default-course tracking behind" >&2
  exit 1
fi

printf 'y\n' | script -qec "bash '$repo_root/bin/ccc' cleanup csci-0300-demo" /dev/null >"$cleanup2_out" 2>&1 || {
  cat "$cleanup2_out" >&2
  exit 1
}

if grep -q 'The shared default container is still used by:' "$cleanup2_out"; then
  cat "$cleanup2_out" >&2
  echo "FAIL: second cleanup repeated the shared default container warning" >&2
  exit 1
fi

if ! grep -q 'Delete the shared default container? \[y/N\]' "$cleanup2_out"; then
  cat "$cleanup2_out" >&2
  echo "FAIL: second cleanup did not fall back to the shorter prompt" >&2
  exit 1
fi

echo "PASS: repeated shared-default cleanup no longer repeats the same warning"