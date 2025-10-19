#!/bin/bash
# Container management functions (from run-podman)

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

# Image management
build_image() {
  if has_image; then
    echo "Image '$IMAGE_NAME' already exists. Skipping build."
    return 0
  fi

  echo "Building $CONTAINER_RUNTIME image '$IMAGE_NAME' for $PLATFORM..."
  echo_and_run "$CONTAINER_RUNTIME" build -t "$IMAGE_NAME" -f "$CONTAINERFILE_PATH" --platform "${PLATFORM}" .
  if [[ $? -ne 0 ]]; then exit 1; fi
}

remove_image() {
  echo "Removing image '$IMAGE_NAME'..."
  echo_and_run "$CONTAINER_RUNTIME" image rm --force "$IMAGE_NAME"
}

# Container management
remove_containers() {
  local _name="${1:-${CONTAINER_NAME}}"
  echo "Removing all existing '$CONTAINER_NAME' containers..."
  "$CONTAINER_RUNTIME" ps -a -f name=${_name} --format "{{.ID}}" | while read line; do
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
    --platform "$PLATFORM" \
    --network "${NETWORK_NAME}" \
    --privileged \
    --passwd \
    --group-entry "$group::$gid:$user" \
    --passwd-entry "$user::$uid:$gid:Default User:/home/courses:/bin/bash" \
    --userns keep-id:uid=$uid,gid=$gid \
    --entrypoint /bin/bash \
    --security-opt seccomp=unconfined \
    --cap-add=SYS_PTRACE \
    --cap-add=NET_ADMIN \
    --volume "$VOLUME_PATH":/home/courses \
    --workdir /home/courses \
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