#!/usr/bin/env sh
# Session bookkeeping helpers shared by open/cleanup flows.

get_session_file() {
    cfgdir=$(resolve_config_dir) || return 1
    echo "$cfgdir/session.json"
}

write_session() {
    course=$1
    container_id=${2:-}
    pid=${3:-}
    start_time=$(date --iso-8601=seconds 2>/dev/null || date +%s)
    session_file=$(get_session_file) || return 1
    printf '{"course":"%s","container_id":"%s","pid":"%s","start":"%s"}\n' "$course" "$container_id" "$pid" "$start_time" >"$session_file"
    chmod 600 "$session_file" 2>/dev/null || true
}

clear_session() {
    session_file=$(get_session_file 2>/dev/null || true)
    if [ -n "$session_file" ]; then
        rm -f "$session_file" 2>/dev/null || true
    fi
}

get_session_course() {
    session_file=$(get_session_file 2>/dev/null || true)
    if [ -z "$session_file" ] || [ ! -f "$session_file" ]; then
        return 1
    fi

    sed -n 's/.*"course":"\([^"]*\)".*/\1/p' "$session_file" | head -n1
}

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