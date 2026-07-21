#!/usr/bin/env sh
# Unified open flow for CCC (local and container)
# Functions:
#  - ccc_open <course_id> [--local] [--no-shell]

## NOTE: `share/open.sh` is a small orchestrator expected to be sourced by
## `ccc.sh`. `ccc.sh` should set `SCRIPT_DIR` and pre-load core libraries
## (utils, config, registry, courses, runtime, session). This file intentionally
## avoids re-sourcing those libraries to stay minimal.

build_course_shell_command() {
    course_id="$1"
    course_dir="/courses/$course_id"
    course_env_file="/courses/$course_id/dev-specs/env/course.env"
    printf "mkdir -p '%s' && cd '%s' && if [ -f '%s' ]; then . '%s'; fi; export CCC_MANAGED_ENV=true; export CCC_COURSES_DIR=/courses; exec bash -l" "$course_dir" "$course_dir" "$course_env_file" "$course_env_file"
}

ccc_cleanup_environment() {
    reason=${1:-shell-exit}
    export CCC_MANAGED_ENV=false
    if [ "$reason" != "shell-exit" ]; then
        echo "Cleaning up stale course environment ($reason)" >&2
    fi
    return "${2:-0}"
}

is_managed_environment() {
    if [ "${CCC_MANAGED_ENV:-}" = "true" ]; then
        return 0
    fi
    return 1
}

report_installer_failure() {
    course_id="$1"
    host_course_dir="$2"
    container_course_dir="$3"
    rc="$4"

    echo "Course installer failed for $course_id (exit code: $rc)." >&2
    echo "Check install logs for details:" >&2
    echo "  Host: $host_course_dir/dev-specs/setup/install.log" >&2
    echo "  Container: $container_course_dir/dev-specs/setup/install.log" >&2
}

sync_course_checkout() {
    course_id="$1"
    course_dir="$2"
    entry=$(registry_lookup "$course_id") || true
    repo_url=$(printf '%s' "$entry" | awk -F',' '{print $2}')
    checkout_was_new=false

    if [ ! -d "$course_dir" ]; then
        if [ -n "$repo_url" ]; then
            echo "Cloning $repo_url -> $course_dir"
            if command -v git >/dev/null 2>&1; then
                git clone "$repo_url" "$course_dir" || { echo "git clone failed" >&2; return 3; }
                checkout_was_new=true
            else
                echo "git not found; cannot clone course" >&2
                return 4
            fi
        else
            echo "Creating course directory for $course_id at $course_dir"
            mkdir -p "$course_dir" || return 5
            checkout_was_new=true
        fi
    fi

    if [ ! -d "$course_dir/.git" ]; then
        return 0
    fi

    if [ "$checkout_was_new" = "true" ]; then
        return 0
    fi

    entry=$(registry_lookup "$course_id") || true
    default_branch=$(printf '%s' "$entry" | awk -F',' '{print $9}')
    if [ -z "$default_branch" ]; then
        default_branch="main"
    fi

    update_checkout=false
    if [ "${CCC_AUTO_UPDATE:-false}" = "true" ]; then
        update_checkout=true
    elif [ -t 0 ] && [ -t 1 ]; then
        printf "Update %s from git before opening it? [Y/n] " "$course_id"
        read -r answer
        case "${answer:-y}" in
            [nN]|[nN][oO])
                update_checkout=false
                ;;
            *)
                update_checkout=true
                ;;
        esac
    fi

    if [ "$update_checkout" != "true" ]; then
        return 0
    fi

    echo "Updating $course_id from git"
    if command -v git >/dev/null 2>&1; then
        if [ -n "$default_branch" ]; then
            git -C "$course_dir" pull --ff-only --quiet origin "$default_branch" || return 1
        else
            git -C "$course_dir" pull --ff-only --quiet || return 1
        fi
    else
        echo "git not found; cannot auto-update course repo" >&2
        return 4
    fi
}

stop_container_for_course() {
    course_id="$1"
    if [ -z "${course_id:-}" ]; then
        return 0
    fi

    container_name="$(get_container_name "$course_id")"
    if [ -z "${container_name:-}" ]; then
        return 0
    fi

    if command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1 2>/dev/null; then
        :
    fi

    if [ -n "${CONTAINER_RUNTIME:-}" ]; then
        if "$CONTAINER_RUNTIME" container exists "$container_name" >/dev/null 2>&1; then
            "$CONTAINER_RUNTIME" stop "$container_name" >/dev/null 2>&1 || true
        fi
    fi
}

start_container_for_course() {
    course_id="$1"

    # Determine image/container names
    CONTAINER_RUNTIME=$(detect_container_runtime) || return 2
    NETWORK_NAME="${CCC_NETWORK_NAME:-net-ccc}"

    # Ensure image/container name defaults exist so runtime helpers don't hit
    # unbound-variable errors
    CCC_IMAGE_PREFIX="${CCC_IMAGE_PREFIX:-ccc}"
    IMAGE_NAME="${IMAGE_NAME:-$CCC_IMAGE_PREFIX}"
    CONTAINER_NAME="$(get_container_name "$course_id")"

    # Determine architecture/platform, defaulting to the machine architecture
    PLATFORM="$(get_course_container_platform "$course_id")"
    case "$PLATFORM" in
      linux/arm64) ARCH="arm64" ;;
      linux/amd64) ARCH="amd64" ;;
      *) ARCH="$(uname -m)" ;;
    esac

    # Build or pull image based on registry image mode
    base_image=$(get_course_build_base_image "$course_id") || base_image="$CCC_DEFAULT_BASE_IMAGE"
    image_name="$(get_image_name "$course_id")"

    build_image "$base_image" "$image_name" "$course_id" || return 3

    CONTAINER_WORKDIR="${CCC_MOUNT_PATH:-/courses}/$course_id"
    start_new_container
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "Failed to start container" >&2
        return $rc
    fi
    return 0
}

ccc_open() {
    course_id="$1"
    shift || true
    mode="local"
    no_shell=false
    while [ "${1:-}" != "" ]; do
        case "$1" in
            --local) mode="local"; shift ;;
            --no-shell) no_shell=true; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$course_id" ]; then
        echo "Usage: ccc open <course> [--local] [--no-shell]" >&2
        return 2
    fi
    # Do not allow nested shells
    if is_managed_environment; then
        echo "You are already inside another CCC-managed course environment. Exit it first before opening $course_id." >&2
        return 1
    fi
    course_dir="$CCC_COURSES_DIR/$course_id"
    mkdir -p "$course_dir" || return 1

    # Ensure course exists in registry
    ensure_course_exists "$course_id" || return 1

    # Clone on first open, otherwise optionally update existing checkouts.
    sync_course_checkout "$course_id" "$course_dir/dev-specs" || return $?

    # Detect whether the registry says this course requires a container.
    requires=$(get_course_requires_container "$course_id") || requires="true"
    if [ "$requires" = "true" ]; then
        mode="container"
    fi
    # Local Path
    if [ "$mode" = "local" ]; then
        # Local mode only opens the course directory and session; standardized
        # course setup is handled by the installer/manifests in container mode.
        export CCC_MANAGED_ENV=true
        if [ "$no_shell" = "true" ]; then
            echo "Opened $course_id (local, no-shell)"
            return 0
        fi
        echo "Entering local course directory: $course_dir"
        cd "$course_dir" || return 1
        "$SHELL" --login
        rc=$?
        ccc_cleanup_environment "shell-exit" "$rc"
        return "$rc"
    # Container Path
    else
        # Ask user for consent before creating/starting a container
        # when running interactively. If stdin is not a tty, assume yes.
        if [ -t 0 ]; then
            printf "Course %s requires a container. Create/start it now? [Y/n] " "$course_id"
            read -r _ans
            case "${_ans:-y}" in
                [yY]|[yY][eE][sS]|"")
                    ;; # proceed
                *)
                    echo "Aborting: container required for $course_id." >&2
                    return 1
                    ;;
            esac
        fi

        # start or reuse the container first, then run the
        # standardized course installer inside the running container.
        start_container_for_course "$course_id" || return $?

        # Ensure runtime vars are set by start_container_for_course
        CONTAINER_NAME="${CONTAINER_NAME:-$(hostname 2>/dev/null || echo "$course_id")}" 
        export CCC_MANAGED_ENV=true
        host_course_dir="${CCC_COURSES_DIR:-$HOME/courses}/$course_id"
        container_course_dir="/courses/$course_id"
        mkdir -p "$host_course_dir" 2>/dev/null || true

        # Use a fixed internal installer location that is independent of the
        # course repository layout. The installer reads
        # `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt`.
        INSTALLER_PATH="/usr/local/share/ccc/course_installer.sh"
        host_course_dir="${CCC_COURSES_DIR:-$HOME/courses}/$course_id"
        container_course_dir="${CONTAINER_WORKDIR:-/courses/$course_id}"
        echo "Running course installer inside container: $CONTAINER_NAME"
        if "$CONTAINER_RUNTIME" exec -i --user 0 -e CCC_MANAGED_ENV=true -e CCC_COURSES_DIR=/courses "$CONTAINER_NAME" bash -lc "if [ -x '$INSTALLER_PATH' ]; then '$INSTALLER_PATH' '$container_course_dir'; else echo 'Installer not found at $INSTALLER_PATH' >&2; exit 2; fi" ; then
            rc=0
        else
            rc=$?
        fi
        if [ "$rc" -ne 0 ]; then
            report_installer_failure "$course_id" "$host_course_dir" "$container_course_dir" "$rc"
            return "$rc"
        fi

        if [ "$(get_course_image_mode "$course_id")" = "default" ]; then
            track_default_container_course "$course_id" || return $?
        fi

        if [ "$no_shell" = "true" ]; then
            echo "Opened $course_id (container, no-shell)"
            return 0
        fi

        shell_cmd="$(build_course_shell_command "$course_id")"

        echo "Attaching to container: $CONTAINER_NAME"
        if [ -t 0 ] && [ -t 1 ]; then
            "$CONTAINER_RUNTIME" exec -it -e CCC_MANAGED_ENV=true -e CCC_COURSES_DIR=/courses "$CONTAINER_NAME" bash -lc "$shell_cmd"
            rc=$?
        else
            "$CONTAINER_RUNTIME" exec -i -e CCC_MANAGED_ENV=true -e CCC_COURSES_DIR=/courses "$CONTAINER_NAME" bash -lc "$shell_cmd"
            rc=$?
        fi
        ccc_cleanup_environment "shell-exit" "$rc"
        return "$rc"
    fi
}