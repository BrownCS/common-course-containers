#!/usr/bin/env sh
# Explicit cleanup flow for CCC course environments.

get_course_dir() {
    course_id="$1"
    echo "${CCC_COURSES_DIR:-$HOME/courses}/$course_id"
}

remove_course_runtime_files() {
    course_dir="$1"

    rm -f \
    "$course_dir/.ccc-installer-ran" \
        "$course_dir/setup/install.log" \
        "$course_dir/env/course.env" \
        2>/dev/null || true
}

remove_course_container() {
    course_id="$1"

    CONTAINER_RUNTIME=$(detect_container_runtime 2>/dev/null || true)
    if [ -z "${CONTAINER_RUNTIME:-}" ]; then
        return 0
    fi

    container_name="$(get_container_name "$course_id")"
    if [ -z "$container_name" ]; then
        return 0
    fi

    if "$CONTAINER_RUNTIME" container exists "$container_name" >/dev/null 2>&1; then
        "$CONTAINER_RUNTIME" stop "$container_name" >/dev/null 2>&1 || true
        "$CONTAINER_RUNTIME" rm -f "$container_name" >/dev/null 2>&1 || true
    fi
}

remove_course_image() {
    course_id="$1"

    image_mode=$(get_course_image_mode "$course_id") || image_mode="default"
    if [ "$image_mode" != "course-specific" ]; then
        return 0
    fi

    CONTAINER_RUNTIME=$(detect_container_runtime 2>/dev/null || true)
    if [ -z "${CONTAINER_RUNTIME:-}" ]; then
        return 0
    fi

    image_name="$(get_image_name "$course_id")"
    if [ -z "$image_name" ]; then
        return 0
    fi

    if "$CONTAINER_RUNTIME" image exists "$image_name" >/dev/null 2>&1; then
        "$CONTAINER_RUNTIME" image rm -f "$image_name" >/dev/null 2>&1 || true
    fi
}

ccc_cleanup_course() {
    course_id="$1"

    if [ -z "$course_id" ]; then
        echo "Usage: ccc cleanup <course>" >&2
        return 2
    fi

    ensure_course_exists "$course_id" || return 1

    course_dir="$(get_course_dir "$course_id")"
    session_file=$(get_session_file 2>/dev/null || true)
    if [ -n "$session_file" ] && [ -f "$session_file" ]; then
        session_course="$(get_session_course 2>/dev/null || true)"
        if [ -z "$session_course" ] || [ "$session_course" = "$course_id" ]; then
            clear_session
        fi
    fi

    remove_course_container "$course_id"
    remove_course_image "$course_id"
    remove_course_runtime_files "$course_dir"

    export CCC_MANAGED_ENV=false
    echo "Cleaned $course_id"
}