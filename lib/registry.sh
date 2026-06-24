#!/usr/bin/env sh
# Minimal registry parsing helpers for CCC
# Usage: registry_lookup <course_id>

# Define Registry File
registry_file="$SCRIPT_DIR/registry.csv"

registry_lookup() {
    course_id=$1
    # Read CSV ignoring comments and blank lines. Match first column exactly.
    awk -F',' -v id="$course_id" 'BEGIN{IGNORECASE=1} /^[[:space:]]*#/ {next} NF>=3 {gsub(/^ +| +$/,"",$1); if($1==id){print $0; exit}}' "$registry_file"
}

registry_list() {
    awk -F',' 'BEGIN{print "Available courses:"} /^[[:space:]]*#/ {next} NF>=3 {print " - " $1 " : " $3}' "$registry_file"
}
