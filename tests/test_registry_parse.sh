#!/usr/bin/env sh
# Simple test for registry parser
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo_root/lib/registry.sh"

out=$(registry_lookup csci-0300-demo)
if [ -z "$out" ]; then
    echo "FAIL: registry_lookup returned empty for csci-0300-demo"
    exit 2
fi

echo "PASS: registry_lookup found: $out"
