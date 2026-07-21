#!/usr/bin/env sh
get_default_container_tracking_file() {
    cfgdir=$(resolve_config_dir) || return 1
    echo "$cfgdir/default-container-courses.txt"
}

list_default_container_courses() {
    tracking_file=$(get_default_container_tracking_file 2>/dev/null || true)
    if [ -z "$tracking_file" ] || [ ! -f "$tracking_file" ]; then
        return 0
    fi

    grep -v '^[[:space:]]*$' "$tracking_file" 2>/dev/null || true
}

track_default_container_course() {
    course_id=$1
    tracking_file=$(get_default_container_tracking_file) || return 1

    touch "$tracking_file" || return 1
    if ! grep -qxF "$course_id" "$tracking_file" 2>/dev/null; then
        printf '%s\n' "$course_id" >>"$tracking_file"
    fi
    chmod 600 "$tracking_file" 2>/dev/null || true
}

untrack_default_container_course() {
    course_id=$1
    tracking_file=$(get_default_container_tracking_file 2>/dev/null || true)
    if [ -z "$tracking_file" ] || [ ! -f "$tracking_file" ]; then
        return 0
    fi

    tmp_file="${tracking_file}.tmp"
    grep -vxF "$course_id" "$tracking_file" 2>/dev/null >"$tmp_file" || true
    if [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$tracking_file"
        chmod 600 "$tracking_file" 2>/dev/null || true
    else
        rm -f "$tmp_file" "$tracking_file"
    fi
}

default_container_course_count() {
    tracking_file=$(get_default_container_tracking_file 2>/dev/null || true)
    if [ -z "$tracking_file" ] || [ ! -f "$tracking_file" ]; then
        echo 0
        return 0
    fi

    awk 'NF{count++} END{print count+0}' "$tracking_file"
}