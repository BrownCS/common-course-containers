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
    "$course_dir/setup/applied-env.txt" \
    "$course_dir/setup/links.manifest" \
    "$course_dir/setup/links.manifest.new" \
    "$course_dir/setup/links.manifest.tmp" \
    "$course_dir/env/course.env" \
    "$course_dir/dev-specs/setup/links.manifest" \
    "$course_dir/dev-specs/setup/links.manifest.new" \
    "$course_dir/dev-specs/setup/links.manifest.tmp" \
    "$course_dir/dev-specs/setup/install.log" \
    "$course_dir/dev-specs/env/course.env" \
        2>/dev/null || true

    rm -rf \
    "$course_dir/bin" \
    "$course_dir/bin.amd64" \
    "$course_dir/bin.native" \
    "$course_dir/env" \
    "$course_dir/dev-specs/bin" \
    "$course_dir/dev-specs/bin.amd64" \
    "$course_dir/dev-specs/bin.native" \
        2>/dev/null || true
}

remove_default_container_runtime_files() {
    while IFS= read -r shared_course; do
        [ -n "$shared_course" ] || continue
        remove_course_runtime_files "$(get_course_dir "$shared_course")"
    done <<EOF
$(list_default_container_courses)
EOF
}

prompt_remove_default_container() {
    remaining_courses="$(list_default_container_courses)"
    if [ -n "$remaining_courses" ]; then
        printf 'The shared default container is still used by:\n%s\n' "$remaining_courses" >&2
        printf 'Delete the shared default container and runtime files for the remaining default courses? [y/N] ' >&2
    else
        printf 'Delete the shared default container? [y/N] ' >&2
    fi

    if [ ! -t 0 ]; then
        echo >&2
        echo "Keeping the shared default container because cleanup is not interactive." >&2
        return 1
    fi

    read -r answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            remove_course_container default
            remove_course_image default
            if [ -n "$remaining_courses" ]; then
                remove_default_container_runtime_files
            fi
            return 0
            ;;
        *)
            echo "Keeping the shared default container and remaining default-course files." >&2
            return 1
            ;;
    esac
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
    legacy_session_file="$(resolve_config_dir 2>/dev/null || true)/session.json"
    rm -f "$legacy_session_file" 2>/dev/null || true

    if [ "$(get_course_image_mode "$course_id")" = "default" ]; then
        untrack_default_container_course "$course_id"
        remove_course_runtime_files "$course_dir"
        prompt_remove_default_container || true
    else
        remove_course_container "$course_id"
        remove_course_image "$course_id"
        remove_course_runtime_files "$course_dir"
    fi

    export CCC_MANAGED_ENV=false
    echo "Cleaned $course_id"
}