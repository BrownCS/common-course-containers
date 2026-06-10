#!/usr/bin/env sh
# Minimal registry parsing helpers for CCC
# Usage: registry_lookup <course_id>

# Prefer SCRIPT_DIR when this file is sourced by the main entrypoint (ccc.sh)
if [ -n "${SCRIPT_DIR:-}" ]; then
    repo_root="$SCRIPT_DIR"
else
    # Fallback: attempt to infer repository root relative to this file; this
    # may not be perfect when sourced from another script, so callers that
    # know the install location should set SCRIPT_DIR before sourcing.
    repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Allow overriding the registry file via environment for tests or deployments
if [ -n "${CCC_REGISTRY_FILE:-}" ]; then
    registry_file="$CCC_REGISTRY_FILE"
else
    registry_file="$repo_root/registry.csv"
fi


registry_lookup() {
    course_id=$1
    # Read CSV ignoring comments and blank lines. Match first column exactly.
    awk -F',' -v id="$course_id" 'BEGIN{IGNORECASE=1} /^[[:space:]]*#/ {next} NF>=3 {gsub(/^ +| +$/,"",$1); if($1==id){print $0; exit}}' "$registry_file"
}

registry_list() {
    awk -F',' 'BEGIN{print "Available courses:"} /^[[:space:]]*#/ {next} NF>=3 {print " - " $1 " : " $3}' "$registry_file"
}
