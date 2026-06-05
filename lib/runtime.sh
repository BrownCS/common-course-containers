#!/bin/bash
set -euo pipefail

# Runtime utilities

get_container_name() {
  local course="${1:-}"
  if [[ -z "$course" ]]; then
    echo "$CONTAINER_NAME"
    return
  fi

  local base_image
  base_image="$(get_course_base_image "$course")"
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

  local base_image
  base_image="$(get_course_base_image "$course")"
  if [[ "$base_image" == "default" || -z "$base_image" ]]; then
    echo "$IMAGE_NAME"
  else
    echo "ccc:$(echo "$base_image" | tr ':' '-')"
  fi
}

check_container_runtime() {
  CONTAINER_RUNTIME=$(detect_container_runtime)
}

has_container() {
  local course="${1:-}"
  local cname
  cname="$(get_container_name "$course")"
  "$CONTAINER_RUNTIME" container exists "$cname" &>/dev/null
}

has_image() {
  local course="${1:-}"
  local iname
  iname="$(get_image_name "$course")"
  "$CONTAINER_RUNTIME" image exists "$iname" &>/dev/null
}

show_course_status() {
  local course="${1:-}"
  local cname iname
  cname="$(get_container_name "$course")"
  iname="$(get_image_name "$course")"

  [[ -n "$course" ]] && echo "Course: $course"
  echo "Image: $iname"
  echo "Container: $cname"
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

build_course_image() {
  local course="${1:-}"
  local iname
  iname="$(get_image_name "$course")"

  local base_image
  base_image="$(get_course_base_image "$course")"
  if [[ "$base_image" == "default" || -z "$base_image" ]]; then
    base_image="$CCC_DEFAULT_BASE_IMAGE"
  fi

  build_image "$base_image" "$iname"
}

# Enter (or create) a container for a course.
# Pass --setup to run the course's setup.sh inside the container.
enter_course() {
  local course="$1"
  local run_setup=false
  [[ "${2:-}" == "--setup" ]] && run_setup=true

  local cname iname course_workdir
  cname="$(get_container_name "$course")"
  iname="$(get_image_name "$course")"
  course_workdir="$CCC_MOUNT_PATH"
  echo "CCC_MOUNT_PATH=${CCC_MOUNT_PATH:-<unset>}"
  [[ "$course" != "default" ]] && course_workdir="$CCC_MOUNT_PATH/$course"

  check_container_runtime
  log_info "Course: $course"
  show_course_status "$course"
  build_course_image "$course"

  local startup_cmd=""
  if $run_setup && [[ "$course" != "default" ]] && [[ -f "$VOLUME_PATH/$course/setup.sh" ]]; then
    startup_cmd="cd '$course_workdir' && sudo apt-get update -y && sudo bash setup.sh"
  fi

  if has_container "$course"; then
    local status
    status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$cname")
    if [[ "$status" != "running" ]]; then
      echo "Starting container '$cname'..."
      "$CONTAINER_RUNTIME" start "$cname"
    fi

    local cmd="cd '$course_workdir' && exec bash"
    [[ -n "$startup_cmd" ]] && cmd="$startup_cmd; exec bash"
    echo_and_run "$CONTAINER_RUNTIME" exec -it "$cname" bash -c "$cmd"
  else
    CONTAINER_NAME="$cname"
    IMAGE_NAME="$iname"
    CONTAINER_WORKDIR="$course_workdir"
    start_new_container "$startup_cmd"
  fi
}