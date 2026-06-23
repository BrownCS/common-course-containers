#!/usr/bin/env sh
# Unified open flow for CCC (local and container)
# Functions:
#  - ccc_open <course_id> [--local] [--no-shell]

## NOTE: `lib/open.sh` is a small orchestrator expected to be sourced by
## `ccc.sh`. `ccc.sh` should set `SCRIPT_DIR` and pre-load core libraries
## (utils, config, registry, courses, runtime). This file intentionally
## avoids re-sourcing those libraries to stay minimal.


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

ccd_clone_if_missing() {
    course_id="$1"
    course_dir="$2"
    entry=$(registry_lookup "$course_id") || true
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
}

# Run course setup inside the host (local) mode — guarded by heuristics
local_setup_if_safe() {
    course_dir="$1"
    if [ -f "$course_dir/setup.sh" ]; then
        if [ -x "$course_dir/setup.sh" ]; then
            # Simple heuristic: don't run setup.sh on host if it references apt or sudo
            if grep -E "\b(apt-get|apt|yum|dnf|sudo)\b" -q "$course_dir/setup.sh"; then
                echo "setup.sh appears to perform system package operations; refusing to run on host. Use container mode." >&2
                return 6
            fi
            (cd "$course_dir" && ./setup.sh) || { echo "setup.sh failed" >&2; return 7; }
        else
            echo "Found setup.sh but it is not executable; skipping" >&2
        fi
    fi
}

start_container_for_course() {
    course_id="$1"
    course_dir="$2"
    # Ensure container runtime helper is available
    if [ -f "$repo_root/lib/container_helpers.sh" ]; then
        # shellcheck disable=SC1090
        . "$repo_root/lib/container_helpers.sh"
    else
        echo "Container helpers not found" >&2
        return
    fi

    # Load runtime helpers
    if [ -f "$repo_root/lib/runtime.sh" ]; then
        # shellcheck disable=SC1090
        . "$repo_root/lib/runtime.sh"
    fi

    # Determine image/container names

    CONTAINER_RUNTIME=$(detect_container_runtime) || return 2
    NETWORK_NAME="${CCC_NETWORK_NAME:-net-ccc}"
    # Normalize CCC_COURSES_DIR leading tilde if present so we compute
    # an absolute host path for binds (avoid creating a literal '~' dir).
    if [ -n "${CCC_COURSES_DIR:-}" ]; then
        case "$CCC_COURSES_DIR" in
            ~/*) CCC_COURSES_DIR="${CCC_COURSES_DIR/#\~/$HOME}" ;;
        esac
        VOLUME_PATH="$(cd "$CCC_COURSES_DIR" >/dev/null 2>&1 && pwd || printf '%s' "$CCC_COURSES_DIR")"
    else
        VOLUME_PATH="$CCC_COURSES_DIR"
    fi

    # Ensure image/container name defaults exist so runtime helpers don't hit
    # unbound-variable errors
    CCC_IMAGE_PREFIX="${CCC_IMAGE_PREFIX:-ccc}"
    IMAGE_NAME="${IMAGE_NAME:-$CCC_IMAGE_PREFIX}"
    CONTAINER_NAME="$(get_container_name "$course_id")"

    # Determine architecture/platform if not set
    if [ -z "${ARCH:-}" ]; then
        ARCH="$(uname -m)"
        if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
            PLATFORM="linux/arm64"
        else
            PLATFORM="linux/amd64"
        fi
    fi

    # Build or pull image based on registry base_image
    base_image=$(get_course_base_image "$course_id") || base_image="default"
    image_name="$(get_image_name "$course_id")"

    if [ "$base_image" != "default" ] && [ -n "$base_image" ]; then
        build_image "$base_image" "$image_name" || return 3
    else
        # ensure default base image built
        build_image "$CCC_DEFAULT_BASE_IMAGE" "$image_name" || return 3
    fi

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
    mode="container"
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

    load_config 2>/dev/null || true
    # Normalize tilde expansion for CCC_COURSES_DIR in case config contains ~
    if [ -n "${CCC_COURSES_DIR:-}" ]; then
        case "$CCC_COURSES_DIR" in
            ~/*) CCC_COURSES_DIR="${CCC_COURSES_DIR/#\~/$HOME}" ;;
        esac
    fi
    if [ -z "${CCC_COURSES_DIR:-}" ]; then
        echo "CCC_COURSES_DIR not configured. Run 'ccc init' or set config." >&2
        return 2
    fi

    course_dir="$CCC_COURSES_DIR/$course_id"
    mkdir -p "$CCC_COURSES_DIR" || return 1

    # Ensure course exists in registry
    ensure_course_exists "$course_id" || return 1

    # Clone if missing
    ccd_clone_if_missing "$course_id" "$course_dir" || return $?

    # Detect if course likely requires a container
    requires=false
    entry=$(registry_lookup "$course_id" 2>/dev/null) || true
    # optional 6th column is requires_container
    requires_field=$(printf '%s' "$entry" | awk -F',' '{print $6}')
    if [ "${requires_field:-}" = "true" ]; then
        requires=true
    fi
    # Heuristic: if setup.sh mentions apt/sudo/direnv then prefer container
    if [ -f "$course_dir/setup.sh" ]; then
        if grep -E "\b(apt-get|apt|yum|dnf|sudo|direnv)\b" -q "$course_dir/setup.sh"; then
            requires=true
        fi
    fi

    if [ "$mode" = "local" ] && [ "$requires" = "true" ]; then
        # Prompt the student to enter container instead
        printf 'This course appears to require a containerized environment. Enter container? [Y/n] '
        read -r answer
        case "$answer" in
            [nN]|[nN][oO])
                echo "Aborting: course setup requires container. To force local, run: ccc open $course_id --local --force-host"
                return 1
                ;;
            *)
                mode="container"
                ;;
        esac
    fi

    if [ "$mode" = "local" ]; then
        # Never automatically run setup.sh on the host. If present, run it
        # only after dropping the user into a host shell (handled by user).
        write_session "$course_id" "" "$$"
        if [ "$no_shell" = "true" ]; then
            echo "Opened $course_id (local, no-shell)"
            return 0
        fi
        echo "Entering local course directory: $course_dir"
        cd "$course_dir" || return 1
        exec "$SHELL" --login
    else
        # Container path: always start the container first, then run setup
        # inside the running container. Prompt the user before starting.
        printf 'This course will be run in a container. Start container now? [Y/n] '
        read -r ans
        case "$ans" in
            [nN]|[nN][oO])
                echo "Aborting: container start declined"
                return 1
                ;;
            *)
                ;;
        esac

    start_container_for_course "$course_id" "$course_dir" || return $?

        # Ensure runtime vars are set by start_container_for_course
        write_session "$course_id" "$CONTAINER_NAME" ""

        # Copy the cooker installer into the course setup dir on the host so
        # it is visible inside the container via the course bind mount. Then
        # execute the installer inside the running container. The installer
        # will read `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt`.
        if [ -f "$repo_root/lib/course_installer.sh" ]; then
            echo "Installing course installer into $course_dir/setup"
            mkdir -p "$course_dir/setup"
            cp "$repo_root/lib/course_installer.sh" "$course_dir/setup/course_installer.sh"
            chmod +x "$course_dir/setup/course_installer.sh" || true
            echo "Running course installer inside container: $CONTAINER_NAME"
            # Run the installer as root inside the container so it can apt install; use absolute path
            INSTALLER_PATH="$CONTAINER_WORKDIR/setup/course_installer.sh"
            echo_and_run "$CONTAINER_RUNTIME" exec -i --user 0 "$CONTAINER_NAME" bash -c "if [ -x '$INSTALLER_PATH' ]; then '$INSTALLER_PATH' '$CONTAINER_WORKDIR'; else echo 'Installer not found at $INSTALLER_PATH' >&2; exit 2; fi"
        else
            echo "Installer not found; skipping automated setup" >&2
        fi

        if [ "$no_shell" = "true" ]; then
            echo "Opened $course_id (container, no-shell)"
            return 0
        fi

    echo "Attaching to container: $CONTAINER_NAME"
    echo_and_run "$CONTAINER_RUNTIME" exec -it "$CONTAINER_NAME" bash -l
    fi
}
