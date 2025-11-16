#!/bin/bash
set -euo pipefail
# Container management functions (from run-podman)

# Container runtime detection and setup
detect_container_runtime() {
  local runtime="podman"

  if ! command -v podman >/dev/null 2>&1; then
    if command -v docker >/dev/null 2>&1; then
      runtime="docker"
    else
      log_error "No container runtime found (podman/docker)"
      return 1
    fi
  fi

  echo "$runtime"
}

# Network management
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
  echo_and_run "$CONTAINER_RUNTIME" build -t "$image_name" -f "$dockerfile_path" --platform "${PLATFORM}" .
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

# Container management
remove_containers() {
  local _name="${1:-${CONTAINER_NAME}}"
  echo "Removing all existing '$CONTAINER_NAME' containers..."
  # Also remove any course-specific containers (ccc-* pattern)
  "$CONTAINER_RUNTIME" ps -a -f name=ccc --format "{{.ID}}" | while read line; do
    echo_and_run "$CONTAINER_RUNTIME" rm --force $line
  done
}

# Container status and info
show_container_status() {
  echo "Image: $IMAGE_NAME"
  echo "Container: $CONTAINER_NAME"
  echo "Volume: $VOLUME_PATH"
  echo "Network: $NETWORK_NAME"
  echo "Arch: $ARCH"
  echo "Runtime: $CONTAINER_RUNTIME"
  echo ""

  echo "Has runtime? $(command -v "$CONTAINER_RUNTIME" >/dev/null && echo YES || echo_error NO)"
  echo "Built image? $(has_image && echo YES || echo_error NO)"
  echo "Set up container? $(has_container && echo YES || echo_error NO)"
  echo "Created network? $(has_network && echo YES || echo_error NO)"
  echo ""
}

# X11 forwarding setup
do_xhost() {
  if $(which xhost); then
    xhost $@
  else
    echo "Warning: xhost was not detected on your system. You may have issues running graphical apps like QEMU or Wireshark."
  fi
}

setup_xhost() {
  if test "$(uname)" = Linux; then
    if grep -qi Microsoft /proc/version; then # Windows
      true                                    # Nothing to do, configured in GUI outside WSL
    else                                      # Native Linux
      if test -n "$DISPLAY"; then
        do_xhost +local:
      else
        # Don't bother doing anything if $DISPLAY isn't set--this might be a headless system
        echo "$DISPLAY is not set, skipping X11 configuration"
      fi
    fi
  elif test "$(uname)" = Darwin; then # Mac OS
    do_xhost +localhost
  fi
}

# Container status helpers
container_is_running() {
  local container_name="$1"
  local status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "missing")
  [[ "$status" == "running" ]]
}

# Container lifecycle management
start_new_container() {
  netarg=
  # TODO: add port mappings if needed
  # add_port_if_open 6169 # 300
  # add_port_if_open 12949 # 300
  # add_port_if_open 9269 # 1680

  # SSH agent forwarding (macOS only)
  ssharg=
  sshenvarg=
  if test -n "$SSH_AUTH_SOCK" -a "$(uname)" = Darwin; then
    ssharg=" -v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock"
    sshenvarg=" -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock"
  fi

  # X11 forwarding setup
  x11arg=
  x11envarg=
  if test "$(uname)" = Linux; then
    if grep -qi Microsoft /proc/version; then # Windows
      x11arg=""
      x11envarg="-e DISPLAY=host.docker.internal:0"
    else # Native Linux
      if test -n "$DISPLAY"; then
        x11arg="-v /tmp/.X11-unix:/tmp/.X11-unix"
        x11envarg="-e DISPLAY=unix$DISPLAY"
      else
        echo "$DISPLAY is not set, skipping X11 configuration"
      fi
    fi
  elif test "$(uname)" = Darwin; then # Mac OS
    x11arg=""
    x11envarg="-e DISPLAY=host.docker.internal:0"
  fi

  # Add any necessary xhost configs
  setup_xhost

  # Create network if it doesn't exist
  create_network

  # Set up user
  local user="$(id -un)"
  local group="$(id -gn)"
  local uid="$(id -u)"
  local gid="$(id -g)"

  # Create the container
  echo "Creating and starting container '$CONTAINER_NAME'..."
  echo_and_run "$CONTAINER_RUNTIME" run \
    --interactive \
    --tty \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --platform "$PLATFORM" \
    --network "${NETWORK_NAME}" \
    --privileged \
    --passwd \
    --group-entry "$group::$gid:$user" \
    --passwd-entry "$user::$uid:$gid:Default User:/home/$user:/bin/bash" \
    --userns keep-id:uid=$uid,gid=$gid \
    --entrypoint /bin/bash \
    --security-opt seccomp=unconfined \
    --cap-add=SYS_PTRACE \
    --cap-add=NET_ADMIN \
    --volume "$VOLUME_PATH":/courses \
    --workdir "${CONTAINER_WORKDIR:-/courses}" \
    --env DIRENV_CONFIG=/root/.config/direnv \
    $sshenvarg \
    $netarg \
    $x11arg $x11envarg \
    "$IMAGE_NAME"

  if [[ $? -ne 0 ]]; then exit 1; fi
}

start_container() {
  STATUS=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$CONTAINER_NAME")
  if [[ "$STATUS" == "running" ]]; then
    echo "Container '$CONTAINER_NAME' is already running. Attaching..."
    echo_and_run "$CONTAINER_RUNTIME" exec -it "$CONTAINER_NAME" bash
  else
    echo "Container '$CONTAINER_NAME' exists but is not running. Starting..."
    echo_and_run "$CONTAINER_RUNTIME" start -ai "$CONTAINER_NAME"
  fi
}

run_container() {
  if ! [[ -d courses ]]; then
    mkdir courses
  fi

  if has_container; then
    start_container
  else
    start_new_container
  fi
}
