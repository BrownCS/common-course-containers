#!/usr/bin/env sh
# Minimal registry parsing helpers for CCC
# Usage: registry_lookup <course_id>

# Define Registry File
registry_file="${CCC_REGISTRY_FILE:-${REGISTRY_FILE:-}}"
if [ -z "$registry_file" ]; then
    if [ -n "${SCRIPT_DIR:-}" ] && [ -f "$SCRIPT_DIR/registry.csv" ]; then
        registry_file="$SCRIPT_DIR/registry.csv"
    elif [ -f "$(dirname "$0")/../registry.csv" ]; then
        registry_file="$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)/registry.csv"
    else
        registry_file="registry.csv"
    fi
fi

registry_field_index() {
    case "$1" in
        url) echo 2 ;;
        name) echo 3 ;;
        semester) echo 4 ;;
        requires_container) echo 5 ;;
        image_mode) echo 6 ;;
        image_ref) echo 7 ;;
        container_arch) echo 8 ;;
        default_branch) echo 9 ;;
        notes) echo 10 ;;
        all) echo 0 ;;
        *) return 1 ;;
    esac
}

registry_lookup() {
    course_id=$1
    # Read CSV ignoring comments and blank lines. Match first column exactly.
    awk -F',' -v id="$course_id" 'BEGIN{IGNORECASE=1} /^[[:space:]]*#/ {next} NF>=3 {gsub(/^ +| +$/,"",$1); if($1==id){print $0; exit}}' "$registry_file"
}

registry_list() {
    awk -F',' 'BEGIN{print "Available courses:"} /^[[:space:]]*#/ {next} NF>=3 {print " - " $1 " : " $3}' "$registry_file"
}
