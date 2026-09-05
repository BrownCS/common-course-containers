#!/bin/bash
set -euo pipefail

# Container runtime helpers (renamed from container.sh)
# Exported functions (stable API):
#  - detect_container_runtime
#  - has_network, create_network, remove_network
#  - generate_dockerfile, validate_base_image, build_image
#  - remove_image, remove_containers
#  - do_xhost, setup_xhost
#  - start_or_reuse_container
#
# Safety notes:
#  - Defaults aim for user-mapped containers; avoid --privileged unless a course opts in.
#  - Images are built from Dockerfile.template using generate_dockerfile().

# Runtime detection 
detect_container_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi
  log_error "Please install podman to use CCC: https://podman.io" #isn't this also done in install.sh check_dependencies()?
  return 1
}

# Network utilities
has_network() {
  "$CONTAINER_RUNTIME" network inspect "$NETWORK_NAME" &>/dev/null
}

create_network() {
  if has_network; then
    echo "Network '$NETWORK_NAME' exists. Skipping creation."
  else
    echo "Creating container-local network '$NETWORK_NAME'..."
    "$CONTAINER_RUNTIME" network create "$NETWORK_NAME"
  fi
}

remove_network() {
  if has_network; then
    echo "Removing network '$NETWORK_NAME'..."
    echo_and_run "$CONTAINER_RUNTIME" network rm "$NETWORK_NAME"
  else
    echo "Network '$NETWORK_NAME' does not exist."
  fi
}

# Image management
generate_dockerfile() {
  local base_image="${1:-$CCC_DEFAULT_BASE_IMAGE}"
  local arch="${2:-amd64}"
  local template_file="$SCRIPT_DIR/Dockerfile.template"
  local output_file="$SCRIPT_DIR/Dockerfile.generated.$arch"

  if [[ ! -f "$template_file" ]]; then
    echo_error "Dockerfile template not found: $template_file"
    return 1
  fi

  # Generate Dockerfile from template
  sed "s|{{BASE_IMAGE}}|$base_image|g" "$template_file" >"$output_file"
  echo "$output_file"
}

validate_base_image() {
  local base_image="$1"

  # Only support Ubuntu and Debian
  if [[ "$base_image" =~ ^ubuntu: ]] || [[ "$base_image" =~ ^debian: ]]; then
    return 0
  else
    echo_error "Unsupported base image: $base_image"
    echo "Currently supported distro-based base images:"
    echo "  - $CCC_DEFAULT_BASE_IMAGE"
    echo "  - ubuntu:jammy"
    echo "  - ubuntu:focal"
    echo "  - debian:bookworm"
    echo "  - debian:bullseye"
    echo "Course-specific images from the registry bypass this distro check."
    return 1
  fi
}

allow_course_specific_base_image() {
  local course="${1:-}"
  if [[ -z "$course" ]]; then
    return 1
  fi

  local mode
  mode="$(get_course_image_mode "$course")" || mode="default"
  [[ "$mode" == "course-specific" ]]
}

# mac users fail GID checks, commenting out for now
validate_container_identity() {
  local image_name="${1:-$IMAGE_NAME}"
  local uid
  # local gid
  local passwd_entry
  # local group_entry

  uid="$(id -u)"
  # gid="$(id -g)"

  if ! "$CONTAINER_RUNTIME" image exists "$image_name" &>/dev/null; then
    return 0
  fi

  passwd_entry="$($CONTAINER_RUNTIME run --rm --entrypoint /bin/sh "$image_name" -lc "grep -E '^[^:]*:[^:]*:${uid}:' /etc/passwd | head -n 1" 2>/dev/null || true)"
  # group_entry="$($CONTAINER_RUNTIME run --rm --entrypoint /bin/sh "$image_name" -lc "grep -E '^[^:]*:[^:]*:${gid}:' /etc/group | head -n 1" 2>/dev/null || true)"

  if [ -n "$passwd_entry" ]; then # || -n "$group_entry" ]
    echo_error "Host uid/gid conflict with numeric accounts in image '$image_name'."
    if [[ -n "$passwd_entry" ]]; then
      echo_error "  uid $uid already appears in /etc/passwd: $passwd_entry"
    fi
    # if [[ -n "$group_entry" ]]; then
      # echo_error "  gid $gid already appears in /etc/group: $group_entry"
    # fi
    echo_error "Choose a different host account or rebuild the image with non-conflicting ids."
    return 1
  fi
}

get_image_build_stamp() {
  local image_name="${1:-$IMAGE_NAME}"
  local stamp_file="$SCRIPT_DIR/.ccc-image-buildstamp-${image_name//[^A-Za-z0-9._-]/_}"
  local tmp_file
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
  tmp_file="$(mktemp)"
  {
    [ -f "$SCRIPT_DIR/Dockerfile.template" ] && sha256sum "$SCRIPT_DIR/Dockerfile.template"
    [ -f "$SCRIPT_DIR/ccc" ] && sha256sum "$SCRIPT_DIR/ccc"
    [ -f "$repo_root/bin/ccc" ] && sha256sum "$repo_root/bin/ccc"
    [ -f "$SCRIPT_DIR/registry.csv" ] && sha256sum "$SCRIPT_DIR/registry.csv"
    find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | sort | xargs -r sha256sum 2>/dev/null
  } >"$tmp_file"
  local stamp
  stamp=$(sha256sum "$tmp_file" | awk '{print $1}')
  rm -f "$tmp_file"
  printf '%s\n' "$stamp"
  printf '%s\n' "$stamp" >"$stamp_file"
}

build_image() {
  local base_image="${1:-$CCC_DEFAULT_BASE_IMAGE}" # Default to ubuntu:noble
  local image_name="${2:-ccc}"          # Default to ccc
  local course_id="${3:-}"
  local arch="${ARCH}"
  local stamp_file="$SCRIPT_DIR/.ccc-image-buildstamp-${image_name//[^A-Za-z0-9._-]/_}"
  local build_stamp

  # Course-specific registry images are expected to be used directly.
  # Do not rebuild a CCC-generated Debian image around them.
  if allow_course_specific_base_image "$course_id"; then
    echo "Using course-specific image '$image_name'; skipping CCC image rebuild."
    return 0
  fi

  build_stamp="$(get_image_build_stamp "$image_name")"

  # Check if image already exists and matches the current CCC sources.
  if "$CONTAINER_RUNTIME" image exists "$image_name" &>/dev/null; then
    if [ -f "$stamp_file" ] && [ "$(cat "$stamp_file" 2>/dev/null || true)" = "$build_stamp" ]; then
      echo "Image '$image_name' already exists and matches current CCC sources. Skipping build."
      return 0
    fi
    echo "Image '$image_name' is out of date with current CCC sources; rebuilding..."
  fi

  # Validate base image unless this is a course-specific base image that the
  # registry explicitly selected for this course.
  if ! validate_base_image "$base_image"; then
    return 1
  fi

  # Normalize architecture
  if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
    arch="arm64"
  else
    arch="amd64"
  fi

  # Generate Dockerfile from template
  local dockerfile_path
  dockerfile_path="$(generate_dockerfile "$base_image" "$arch")"

  if [[ $? -ne 0 ]]; then
    echo_error "Failed to generate Dockerfile"
    return 1
  fi

  local build_context="$SCRIPT_DIR"
  local temp_context=""
  local repo_root=""

  # When running from a repo checkout, SCRIPT_DIR points to share/ and does
  # not contain the CLI entrypoint file expected by Dockerfile.template.
  # Synthesize a temporary build context that includes `ccc` from repo/bin.
  if [[ ! -f "$SCRIPT_DIR/ccc" ]]; then
    repo_root="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
    if [[ -n "$repo_root" && -f "$repo_root/bin/ccc" ]]; then
      temp_context="$(mktemp -d)"
      cp -a "$SCRIPT_DIR/." "$temp_context/"
      cp "$repo_root/bin/ccc" "$temp_context/ccc"
      build_context="$temp_context"
    fi
  fi

  echo "Building $CONTAINER_RUNTIME image '$image_name' with base '$base_image' for $PLATFORM..."
  echo_and_run "$CONTAINER_RUNTIME" build -t "$image_name" -f "$dockerfile_path" --platform "${PLATFORM}" "$build_context"
  local build_result=$?

  # Cleanup generated Dockerfile
  rm -f "$dockerfile_path"
  if [[ -n "$temp_context" ]]; then
    rm -rf "$temp_context"
  fi

  if [[ $build_result -ne 0 ]]; then
    echo_error "Build failed"
    return 1
  fi

  printf '%s\n' "$build_stamp" >"$stamp_file"
  echo "Successfully built image: $image_name"
}

remove_image() {
  echo "Removing image '$IMAGE_NAME'..."
  echo_and_run "$CONTAINER_RUNTIME" image rm --force "$IMAGE_NAME"
}

remove_containers() {
  echo "Removing all existing '$CONTAINER_NAME' containers..."
  local ids
  ids=$("$CONTAINER_RUNTIME" ps -a -f name=ccc --format "{{.ID}}" 2>/dev/null) || true
  if [[ -n "$ids" ]]; then
    while read -r line; do
      [[ -n "$line" ]] && echo_and_run "$CONTAINER_RUNTIME" rm --force "$line"
    done <<< "$ids"
  else
    echo "No containers found."
  fi
}

# X11 forwarding setup
do_xhost() {
  if command -v xhost >/dev/null 2>&1; then
    xhost "$@"
  else
    echo "Warning: xhost was not detected on your system. You may have issues running graphical apps like QEMU or Wireshark."
  fi
}

setup_xhost() {
  if [[ "$(uname)" == "Linux" ]]; then
    if grep -qi Microsoft /proc/version 2>/dev/null; then
      true
    elif [[ -n "${DISPLAY:-}" ]]; then
      do_xhost +local:
    fi
  elif [[ "$(uname)" == "Darwin" ]]; then
    do_xhost +localhost
  fi
}

start_or_reuse_container() {
  setup_xhost
  create_network

  local user="$(id -un)"
  local uid="$(id -u)"
  local group="$(id -gn)"
  local gid="$(id -g)"

  VOLUME_PATH="${VOLUME_PATH:-${CCC_COURSES_DIR:-${HOME}/courses}}"
  mkdir -p "$VOLUME_PATH" 2>/dev/null || true

  local run_cmd="$CONTAINER_RUNTIME"
  local run_verb="run"
  local interactive_args=( --interactive )
  if [ -t 0 ] && [ -t 1 ]; then
    interactive_args+=( --tty )
  fi

  # If a container with this name already exists, try to reuse it.
  if "$CONTAINER_RUNTIME" container exists "$CONTAINER_NAME" >/dev/null 2>&1; then
    existing_status=$($CONTAINER_RUNTIME inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)
    echo "Container '$CONTAINER_NAME' already exists (status=$existing_status)."
    if [ "$existing_status" = "running" ]; then
      echo "Reusing running container '$CONTAINER_NAME'."
      return 0
    fi

    echo "Attempting to start existing container '$CONTAINER_NAME'..."
    "$CONTAINER_RUNTIME" start "$CONTAINER_NAME" >/dev/null 2>&1 || true
    # wait for running
    attempts=0
    state=""
    while [ $attempts -lt 10 ]; do
      state=$($CONTAINER_RUNTIME inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)
      if [ "$state" = "running" ]; then
        echo "Started container '$CONTAINER_NAME'."
        return 0
      fi
      attempts=$((attempts + 1))
      sleep 0.5
    done

    echo "Container exists but did not reach running state (state=$state)."
    # Ask user whether to remove and recreate the container.
    printf "Container '%s' exists but is not running. Remove and recreate? [y/N] " "$CONTAINER_NAME"
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        echo "Removing container '$CONTAINER_NAME'..."
        "$CONTAINER_RUNTIME" rm --force "$CONTAINER_NAME" || { echo "Failed to remove existing container" >&2; return 1; }
        ;;
      *)
        echo "Aborting: will not remove existing container." >&2
        return 1
        ;;
    esac
    # fall through to create a new container
  fi
  # memory-swap added Aug 13 to help with large package installs
  local run_args=(
    "$run_cmd" "$run_verb"
    --detach
    "${interactive_args[@]}"
    --name "$CONTAINER_NAME"
    --hostname "$CONTAINER_NAME"
    --platform "$PLATFORM"
    --network "${NETWORK_NAME}"
    --privileged
    --entrypoint /bin/bash
    --security-opt seccomp=unconfined
    --cap-add=SYS_PTRACE
    --cap-add=NET_ADMIN
    --memory-swap -1
    --volume "$VOLUME_PATH":"${CONTAINER_MOUNT_PATH:-/courses}"
    --workdir "${CONTAINER_WORKDIR:-${CONTAINER_MOUNT_PATH:-/courses}}"
  )

  # Keep the host user/group identity inside the container and let sudo work
  # via the image's passwordless sudo configuration.
  run_args+=(
    --passwd
    --group-entry "$group::$gid:$user"
    --passwd-entry "$user::$uid:$gid:Default User:/home/$user:/bin/bash"
    --userns "keep-id:uid=$uid,gid=$gid"
  )

  # SSH agent forwarding
  # - On macOS with Docker Desktop, prefer the host-services socket.
  # - Otherwise, forward the user's current SSH_AUTH_SOCK when available.
  local ssh_sock=""
  if [[ "$(uname)" == "Darwin" ]] && [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -e "/run/host-services/ssh-auth.sock" ]]; then
    ssh_sock="/run/host-services/ssh-auth.sock"
  elif [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "${SSH_AUTH_SOCK}" ]]; then
    ssh_sock="${SSH_AUTH_SOCK}"
  fi

  if [[ -n "$ssh_sock" ]]; then
    run_args+=( -v "$ssh_sock:$ssh_sock" )
    run_args+=( -e "SSH_AUTH_SOCK=$ssh_sock" )
  fi

  validate_container_identity "$IMAGE_NAME" || return 1

  # X11 forwarding
  if [[ "$(uname)" == "Linux" ]]; then
    if grep -qi Microsoft /proc/version 2>/dev/null; then
      run_args+=( -e DISPLAY=host.docker.internal:0 )
    elif [[ -n "${DISPLAY:-}" ]]; then
      run_args+=( -v /tmp/.X11-unix:/tmp/.X11-unix )
      run_args+=( -e "DISPLAY=unix$DISPLAY" )
    else
      echo "\$DISPLAY is not set, skipping X11 configuration"
    fi
  elif [[ "$(uname)" == "Darwin" ]]; then
    run_args+=( -e DISPLAY=host.docker.internal:0 )
  fi

  run_args+=( "$IMAGE_NAME" )

  echo "Creating and starting container '$CONTAINER_NAME'..."
  # Execute the run command and capture exit status.
  if echo_and_run "${run_args[@]}"; then
    :
  else
    run_rc=$?
    echo "Container runtime failed to start the container (rc=$run_rc)" >&2
    return $run_rc
  fi
}
