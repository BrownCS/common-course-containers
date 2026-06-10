#!/usr/bin/env sh
# Host-only open flow for CCC
# Functions:
#  - open_host <course_id> [--no-shell]

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

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

open_host() {
    course_id="${1:-}"
    shift 2>/dev/null || true
    no_shell=false
    if [ "${1:-}" = "--no-shell" ]; then
        no_shell=true
    fi

    if [ -z "$course_id" ]; then
        echo "Usage: ccc open <course> [--no-shell]" >&2
        return 2
    fi

    # ensure config loaded
    load_config 2>/dev/null || true

    if [ -z "${CCC_COURSES_DIR:-}" ]; then
        echo "CCC_COURSES_DIR not configured. Run 'ccc init' or set config." >&2
        return 2
    fi

    course_dir="$CCC_COURSES_DIR/$course_id"

    # Ensure courses dir exists
    mkdir -p "$CCC_COURSES_DIR" || return 1

    # If course dir missing and registry provides a repo_url, attempt clone
    entry=$(registry_lookup "$course_id") || true
    # parse second CSV column (repo_url)
    repo_url=$(printf '%s' "$entry" | awk -F',' '{print $2}')
    if [ ! -d "$course_dir" ]; then
        if [ -n "$repo_url" ]; then
            echo "Cloning $repo_url -> $course_dir"
            if command -v git >/dev/null 2>&1; then
                git clone "$repo_url" "$course_dir" || { echo "git clone failed" >&2; return 3; }
            else
                echo "git not found; cannot clone course" >&2
                return 4
            fi
        else
            echo "No repository URL for course $course_id and course directory missing" >&2
            return 5
        fi
    fi

    # Run setup.sh if present and executable
    if [ -f "$course_dir/setup.sh" ]; then
        if [ -x "$course_dir/setup.sh" ]; then
            (cd "$course_dir" && ./setup.sh) || { echo "setup.sh failed" >&2; return 6; }
        else
            echo "Found setup.sh but it is not executable; skipping" >&2
        fi
    fi

    # Write session file; no container for host flow
    write_session "$course_id" "" "$$"

    if [ "$no_shell" = "true" ]; then
        echo "Opened $course_id (no-shell)"
        return 0
    fi

    # Exec a login shell in the course directory
    echo "Entering course environment: $course_id at $course_dir"
    cd "$course_dir" || return 1
    exec "$SHELL" --login
}
