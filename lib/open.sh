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

    build_image "$base_image" "$image_name" || return 3

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

    course_dir="$CCC_COURSES_DIR/$course_id"
    mkdir -p "$CCC_COURSES_DIR" || return 1

    # Ensure course exists in registry
    ensure_course_exists "$course_id" || return 1

    # Clone if missing
    ccd_clone_if_missing "$course_id" "$course_dir" || return $?

    # Detect whether the registry says this course requires a container.
    requires=$(get_course_requires_container "$course_id") || requires="true"
    if [ "$requires" != "true" ]; then
        mode="local"
    else
        mode="container"
    fi

    if [ "$mode" = "local" ]; then
        # Local mode only opens the course directory and session; standardized
        # course setup is handled by the installer/manifests in container mode.
        write_session "$course_id" "" "$$"
        if [ "$no_shell" = "true" ]; then
            echo "Opened $course_id (local, no-shell)"
            return 0
        fi
        echo "Entering local course directory: $course_dir"
        cd "$course_dir" || return 1
        exec "$SHELL" --login
    else
        # Container path: always start the container first, then run the
        # standardized course installer inside the running container.
        if [ -t 0 ] && [ -t 1 ]; then
            printf 'This course will be run in a container. Start container now? [Y/n] '
            read -r ans
        else
            ans='y'
        fi
        case "$ans" in
            [nN]|[nN][oO])
                echo "Aborting: container start declined"
                return 1
                ;;
            *)
                ;;
        esac

    start_container_for_course "$course_id" || return $?

        # Ensure runtime vars are set by start_container_for_course
        write_session "$course_id" "$CONTAINER_NAME" ""

        # Copy the standardized course installer into the course setup dir on
        # the host so it is visible inside the container via the bind mount.
        # Then execute it inside the running container. The installer reads
        # `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt`.
        if [ -f "$SCRIPT_DIR/lib/course_installer.sh" ]; then
            echo "Installing course installer into $course_dir/setup"
            mkdir -p "$course_dir/setup"
            cp "$SCRIPT_DIR/lib/course_installer.sh" "$course_dir/setup/course_installer.sh"
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
    if [ -t 0 ] && [ -t 1 ]; then
        echo_and_run "$CONTAINER_RUNTIME" exec -it "$CONTAINER_NAME" bash -l
    else
        echo_and_run "$CONTAINER_RUNTIME" exec -i "$CONTAINER_NAME" bash -l
    fi
    fi
}