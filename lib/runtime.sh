#!/bin/bash
set -euo pipefail

# Runtime utilities

# Container resolution functions
get_container_name() {
  local course="${1:-}"

  if [[ -z "$course" ]]; then
    echo "$CONTAINER_NAME"
    return
  fi

  local base_image="$(get_course_base_image "$course")"
  if [[ "$base_image" == "default" || -z "$base_image" ]]; then
    echo "$CONTAINER_NAME"
  else
    echo "ccc-$(echo "$base_image" | tr ':' '-')"
  fi
}

get_image_name() {
  local course="${1:-}"

  if [[ -z "$course" ]]; then
    echo "$IMAGE_NAME"
    return
  fi

  local base_image="$(get_course_base_image "$course")"
  if [[ "$base_image" == "default" || -z "$base_image" ]]; then
    echo "$IMAGE_NAME"
  else
    echo "ccc:$(echo "$base_image" | tr ':' '-')"
  fi
}

# Basic container management functions
check_container_runtime() {
  # Auto-detect container runtime
  CONTAINER_RUNTIME=$(detect_container_runtime)
  local result=$?

  if [[ $result -ne 0 ]]; then
    echo "Please install Podman: https://podman.io/getting-started/installation"
    exit 1
  fi

  return 0
}

has_container() {
  local course="${1:-}"
  local container_name
  container_name="$(get_container_name "$course")"
  "$CONTAINER_RUNTIME" container exists "$container_name" &>/dev/null
}

has_image() {
  local course="${1:-}"
  local image_name
  image_name="$(get_image_name "$course")"
  "$CONTAINER_RUNTIME" image exists "$image_name" &>/dev/null
}

# Create or enter a persistent container and run setup.sh if present.
# Cloning is done on the host before calling this (see clone_course).
setup_and_enter_course() {
  local course="$1"
  local container_name
  local image_name
  container_name="$(get_container_name "$course")"
  image_name="$(get_image_name "$course")"

  local course_workdir="$CCC_MOUNT_PATH"
  if [[ "$course" != "default" ]]; then
    course_workdir="$CCC_MOUNT_PATH/$course"
  fi

  check_container_runtime
  log_info "Setting up course: $course"
  show_container_status_for_course "$course"
  build_image_for_course "$course"

  local setup_cmd=""
  if [[ "$course" != "default" ]] && [[ -f "$VOLUME_PATH/$course/setup.sh" ]]; then
    setup_cmd="cd '$course_workdir' && sudo apt-get update -y && sudo bash setup.sh"
  fi

  if has_container "$course"; then
    local status
    status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$container_name")
    if [[ "$status" != "running" ]]; then
      echo "Starting container '$container_name'..."
      "$CONTAINER_RUNTIME" start "$container_name"
    fi

    if [[ -n "$setup_cmd" ]]; then
      echo "Running setup in container..."
      echo_and_run "$CONTAINER_RUNTIME" exec -it "$container_name" \
        bash -c "$setup_cmd; exec bash"
    else
      echo_and_run "$CONTAINER_RUNTIME" exec -it "$container_name" \
        bash -c "cd '$course_workdir' && exec bash"
    fi
  else
    local orig_container_name="$CONTAINER_NAME"
    local orig_image_name="$IMAGE_NAME"
    CONTAINER_NAME="$container_name"
    IMAGE_NAME="$image_name"
    CONTAINER_WORKDIR="$course_workdir"

    start_new_container "$setup_cmd"

    CONTAINER_NAME="$orig_container_name"
    IMAGE_NAME="$orig_image_name"
  fi
}

# Course-specific container management wrapper functions
show_container_status_for_course() {
  local course="$1"
  local container_name
  local image_name
  container_name="$(get_container_name "$course")"
  image_name="$(get_image_name "$course")"

  echo "Course: $course"
  echo "Image: $image_name"
  echo "Container: $container_name"
  echo "Volume: $VOLUME_PATH"
  echo "Network: $NETWORK_NAME"
  echo "Arch: $ARCH"
  echo "Runtime: $CONTAINER_RUNTIME"
  echo ""

  echo "Has runtime? $(command -v "$CONTAINER_RUNTIME" >/dev/null && echo YES || echo_error NO)"
  echo "Built image? $(has_image "$course" && echo YES || echo_error NO)"
  echo "Set up container? $(has_container "$course" && echo YES || echo_error NO)"
  echo "Created network? $(has_network && echo YES || echo_error NO)"
  echo ""
}

build_image_for_course() {
  local course="$1"
  local image_name
  image_name="$(get_image_name "$course")"

  # Get course-specific base image
  local base_image
  base_image="$(get_course_base_image "$course")"

  if [[ "$base_image" == "default" || -z "$base_image" ]]; then
    # Use default base image
    build_image "$CCC_DEFAULT_BASE_IMAGE" "$image_name"
  else
    # Use course-specific base image
    build_image "$base_image" "$image_name"
  fi
}

run_container_for_course() {
  local course="$1"
  local container_name
  local image_name
  container_name="$(get_container_name "$course")"
  image_name="$(get_image_name "$course")"

  # Determine target working directory
  local course_workdir="$CCC_MOUNT_PATH"
  if [[ "$course" != "default" && -d "$VOLUME_PATH/$course" ]]; then
    course_workdir="$CCC_MOUNT_PATH/$course"
  fi

  if has_container "$course"; then
    # Start existing container and cd to appropriate directory
    local status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$container_name")

    if [[ "$status" == "running" ]]; then
      echo "Container '$container_name' is already running. Attaching..."
      echo_and_run "$CONTAINER_RUNTIME" exec -it "$container_name" bash -c "cd '$course_workdir' && exec bash"
    else
      echo "Container '$container_name' exists but is not running. Starting..."
      if [[ "$course" == "default" ]]; then
        # For default, explicitly start and exec to ensure we're in /courses
        echo_and_run "$CONTAINER_RUNTIME" start "$container_name"
        echo_and_run "$CONTAINER_RUNTIME" exec -it "$container_name" bash -c "cd '$course_workdir' && exec bash"
      else
        # For courses, use start -ai to preserve existing behavior
        echo_and_run "$CONTAINER_RUNTIME" start -ai "$container_name"
      fi
    fi
  else
    # Create new interactive container with proper user setup
    # Override globals temporarily to reuse existing function
    local orig_container_name="$CONTAINER_NAME"
    local orig_image_name="$IMAGE_NAME"
    CONTAINER_NAME="$container_name"
    IMAGE_NAME="$image_name"
    CONTAINER_WORKDIR="$course_workdir"

    # Call existing start_new_container function (creates interactive container with user setup)
    start_new_container

    # Restore globals
    CONTAINER_NAME="$orig_container_name"
    IMAGE_NAME="$orig_image_name"
  fi
}