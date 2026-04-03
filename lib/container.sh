#!/bin/bash
set -euo pipefail

# Container management utilities

# Runtime detection 
detect_container_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
  else
    log_error "Please install podman to use CCC: https://podman.io"
    exit 1
  fi
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
    echo "Currently supported base images:"
    echo "  - $CCC_DEFAULT_BASE_IMAGE"
    echo "  - ubuntu:jammy"
    echo "  - ubuntu:focal"
    echo "  - debian:bookworm"
    echo "  - debian:bullseye"
    return 1
  fi
}

build_image() {
  local base_image="${1:-$CCC_DEFAULT_BASE_IMAGE}" # Default to ubuntu:noble
  local image_name="${2:-ccc}"          # Default to ccc
  local arch="${ARCH}"

  # Check if image already exists
  if "$CONTAINER_RUNTIME" image exists "$image_name" &>/dev/null; then
    echo "Image '$image_name' already exists. Skipping build."
    return 0
  fi

  # Validate base image
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

  echo "Building $CONTAINER_RUNTIME image '$image_name' with base '$base_image' for $PLATFORM..."
  echo_and_run "$CONTAINER_RUNTIME" build -t "$image_name" -f "$dockerfile_path" --platform "${PLATFORM}" "$SCRIPT_DIR"
  local build_result=$?

  # Cleanup generated Dockerfile
  rm -f "$dockerfile_path"

  if [[ $build_result -ne 0 ]]; then
    echo_error "Build failed"
    return 1
  fi

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

start_new_container() {
  # Take an optional command to run before dropping to interactive bash
  local startup_cmd="${1:-}"

  setup_xhost
  create_network

  local user="$(id -un)"
  local group="$(id -gn)"
  local uid="$(id -u)"
  local gid="$(id -g)"

  local run_args=(
    "$CONTAINER_RUNTIME" run
    --interactive
    --tty
    --name "$CONTAINER_NAME"
    --hostname "$CONTAINER_NAME"
    --platform "$PLATFORM"
    --network "${NETWORK_NAME}"
    --privileged
    --entrypoint /bin/bash
    --security-opt seccomp=unconfined
    --cap-add=SYS_PTRACE
    --cap-add=NET_ADMIN
    --volume "$VOLUME_PATH":/courses
    --workdir "${CONTAINER_WORKDIR:-/courses}"
    --env DIRENV_CONFIG=/root/.config/direnv
  )

  run_args+=(
    --passwd
    --group-entry "$group::$gid:$user"
    --passwd-entry "$user::$uid:$gid:Default User:/home/$user:/bin/bash"
    --userns "keep-id:uid=$uid,gid=$gid"
  )

  # SSH agent forwarding (macOS Docker only)
  local ssh_sock="/run/host-services/ssh-auth.sock"
  if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ "$(uname)" == "Darwin" ]] && [[ -e "$ssh_sock" ]]; then
    run_args+=(-v "$ssh_sock:$ssh_sock")
    run_args+=(-e "SSH_AUTH_SOCK=$ssh_sock")
  fi

  # X11 forwarding
  if [[ "$(uname)" == "Linux" ]]; then
    if grep -qi Microsoft /proc/version 2>/dev/null; then
      run_args+=(-e DISPLAY=host.docker.internal:0)
    elif [[ -n "${DISPLAY:-}" ]]; then
      run_args+=(-v /tmp/.X11-unix:/tmp/.X11-unix)
      run_args+=(-e "DISPLAY=unix$DISPLAY")
    else
      echo "\$DISPLAY is not set, skipping X11 configuration"
    fi
  elif [[ "$(uname)" == "Darwin" ]]; then
    run_args+=(-e DISPLAY=host.docker.internal:0)
  fi

  run_args+=("$IMAGE_NAME")

  if [[ -n "$startup_cmd" ]]; then
    run_args+=(-c "$startup_cmd; exec bash")
  fi

  echo "Creating and starting container '$CONTAINER_NAME'..."
  echo_and_run "${run_args[@]}"
}
