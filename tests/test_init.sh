#!/usr/bin/env sh
# Smoke test for ccc init (non-interactive simulation)
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"

# Use a temp HOME to avoid clobbering real user config
TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"

# Run prompt_init non-interactively by simulating reads
# Provide inputs using a here-doc
printf "%s\n%s\n" "$HOME/courses" "n" | prompt_init >/dev/null 2>&1

cfg=$(get_config_file)
if [ ! -f "$cfg" ]; then
    echo "FAIL: config file not written"
    exit 2
fi

. "$cfg"
if [ "$CCC_INSTALL_MODE" != "git" ]; then
    echo "FAIL: CCC_INSTALL_MODE not set to git"
    exit 2
fi

echo "PASS: init wrote config to $cfg"
