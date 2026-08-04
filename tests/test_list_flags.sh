#!/usr/bin/env sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT HUP INT TERM

export HOME="$TMP_HOME"
export CCC_COURSES_DIR="$TMP_HOME/courses"

mkdir -p "$CCC_COURSES_DIR/alpha" "$CCC_COURSES_DIR/beta"

avail_output="$(bash "$repo_root/bin/ccc" list --avail)"
installed_output="$(bash "$repo_root/bin/ccc" list --installed)"

if ! printf '%s\n' "$avail_output" | grep -q '^Available courses:'; then
  echo "FAIL: list --avail did not print the available-courses header" >&2
  exit 2
fi

if ! printf '%s\n' "$installed_output" | grep -q '^Installed courses:'; then
  echo "FAIL: list --installed did not print the installed-courses header" >&2
  exit 2
fi

if ! printf '%s\n' "$installed_output" | grep -q 'alpha'; then
  echo "FAIL: list --installed did not include alpha" >&2
  exit 2
fi

if ! printf '%s\n' "$installed_output" | grep -q 'beta'; then
  echo "FAIL: list --installed did not include beta" >&2
  exit 2
fi

if bash "$repo_root/bin/ccc" list --bogus >/dev/null 2>&1; then
  echo "FAIL: list --bogus should fail" >&2
  exit 2
fi

echo "PASS: ccc list supports avail and installed flags"