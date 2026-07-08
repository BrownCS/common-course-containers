#!/usr/bin/env sh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT HUP INT TERM

registry_lookup() {
  echo "default,,Default Container,always,true,default,,,"
}

resolve_config_dir() {
  echo "$tmpdir"
}

. "$repo_root/share/open.sh"

course_dir="$tmpdir/default-course"
rm -rf "$course_dir"
ccd_clone_if_missing default "$course_dir"

if [ ! -d "$course_dir" ]; then
  echo "FAIL: default course with no repo URL should create a course directory" >&2
  exit 2
fi

echo "PASS: default course with no repo URL is handled"
