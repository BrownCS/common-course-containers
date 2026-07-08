#!/usr/bin/env sh
# Test auto-update CLI subcommand
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/share/config.sh"

# Use a temp HOME
TMP_HOME="$(mktemp -d)"
export HOME="$TMP_HOME"

# Ensure config exists
printf "%s\n%s\n" "$HOME/courses" "n" | prompt_init >/dev/null 2>&1

# Run enable
"$repo_root/ccc.sh" auto-update enable >/dev/null 2>&1
. "$(get_config_file)"
if [ "$CCC_AUTO_UPDATE" != "true" ]; then
    echo "FAIL: auto-update enable did not set config"
    exit 2
fi

# Run status
out=$("$repo_root/ccc.sh" auto-update status)
if [ "$out" != "CCC_AUTO_UPDATE=true" ]; then
    echo "FAIL: status returned: $out"
    exit 2
fi

# Run disable
"$repo_root/ccc.sh" auto-update disable >/dev/null 2>&1
. "$(get_config_file)"
if [ "$CCC_AUTO_UPDATE" != "false" ]; then
    echo "FAIL: auto-update disable did not set config"
    exit 2
fi

echo "PASS: auto-update commands work"
