#!/usr/bin/env sh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TMP_ORIGIN="$(mktemp -d)"
TMP_WORK="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_HOME" "$TMP_ORIGIN" "$TMP_WORK"
}
trap cleanup EXIT HUP INT TERM

export HOME="$TMP_HOME"
export CCC_REGISTRY_FILE="$TMP_HOME/registry.csv"

. "$repo_root/share/config.sh"

mkdir -p "$TMP_HOME/courses"
set_config CCC_AUTO_UPDATE true
set_config CCC_COURSES_DIR "$TMP_HOME/courses"

git init --bare "$TMP_ORIGIN/origin.git" >/dev/null 2>&1

git init "$TMP_WORK/seed" >/dev/null 2>&1
git -C "$TMP_WORK/seed" config user.name "CCC Test"
git -C "$TMP_WORK/seed" config user.email "ccc@example.invalid"
printf 'version one\n' >"$TMP_WORK/seed/README.md"
git -C "$TMP_WORK/seed" add README.md
git -C "$TMP_WORK/seed" commit -m "initial" >/dev/null 2>&1
git -C "$TMP_WORK/seed" branch -M main
git -C "$TMP_WORK/seed" remote add origin "$TMP_ORIGIN/origin.git"
git -C "$TMP_WORK/seed" push -u origin main >/dev/null 2>&1

cat >"$CCC_REGISTRY_FILE" <<EOF
auto-update-course,file://$TMP_ORIGIN/origin.git,Auto Update Course,demo,false,default,,,main,Auto-update test course
EOF

bash "$repo_root/ccc.sh" open auto-update-course --no-shell >/dev/null 2>&1

printf 'version two\n' >"$TMP_WORK/seed/README.md"
git -C "$TMP_WORK/seed" add README.md
git -C "$TMP_WORK/seed" commit -m "update" >/dev/null 2>&1
git -C "$TMP_WORK/seed" push origin main >/dev/null 2>&1

bash "$repo_root/ccc.sh" open auto-update-course --no-shell >/dev/null 2>&1

if ! grep -q 'version two' "$TMP_HOME/courses/auto-update-course/README.md"; then
  echo "FAIL: auto-update did not pull the latest commit" >&2
  exit 2
fi

echo "PASS: ccc open auto-updates existing course checkouts when enabled"