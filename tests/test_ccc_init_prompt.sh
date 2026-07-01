#!/usr/bin/env sh
# Test running ccc.sh init non-interactively by simulating input
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"

# Simulate user providing empty input (accept defaults) and 'n' for auto-update
printf "\n n\n" | "$repo_root/ccc.sh" init >/dev/null 2>&1

cfg=$(cd "$TMP_HOME" && ./.ccc/config 2>/dev/null || true; echo "$TMP_HOME/.ccc/config")
if [ ! -f "$cfg" ]; then
    echo "FAIL: config not written by ccc init"
    exit 2
fi

. "$cfg"
if [ -z "$CCC_COURSES_DIR" ]; then
    echo "FAIL: CCC_COURSES_DIR not set"
    exit 2
fi

echo "PASS: ccc init wrote config"
