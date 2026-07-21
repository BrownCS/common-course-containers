#!/bin/bash
set -euo pipefail

# Runtime utilities

get_container_name() {
  local course="${1:-}"
  if [[ -n "$course" ]]; then
    local image_mode
    image_mode="$(get_course_image_mode "$course")" || image_mode="default"
    # Shared courses use one reusable runtime named `default`; course-specific
    # courses keep their own dedicated runtime.
    if [[ "$image_mode" == "course-specific" ]]; then
      echo "ccc-${course}"
    else
      echo "default"
    fi
    return 0
  fi

  # No course provided: prefer explicit CONTAINER_NAME, else the image prefix.
  local prefix="${CCC_IMAGE_PREFIX:-ccc}"
  # No course provided: prefer explicit CONTAINER_NAME, else the prefix.
  if [[ -n "${CONTAINER_NAME:-}" ]]; then
    echo "${CONTAINER_NAME}"
  else
    echo "${prefix}"
  fi
}

get_image_name() {
  local course="${1:-}"
  if [[ -z "$course" ]]; then
    echo "${IMAGE_NAME:-ccc}"
    return
  fi

  local image_mode
  image_mode="$(get_course_image_mode "$course")"
  if [[ "$image_mode" == "course-specific" ]]; then
    echo "ccc-${course}"
  else
    echo "${IMAGE_NAME:-ccc}"
  fi
}

get_course_platform() {
  local course="${1:-}"
  if [[ -z "$course" ]]; then
    case "$(uname -m)" in
      arm64|aarch64) echo "linux/arm64" ;;
      *) echo "linux/amd64" ;;
    esac
    return
  fi

  get_course_container_platform "$course"
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
  echo "building course"
  local course="${1:-}"
  local iname
  iname="$(get_image_name "$course")"

  local base_image
  base_image="$(get_course_build_base_image "$course")"

  build_image "$base_image" "$iname" "$course"
}

# Enter (or create) a container for a course.
# The standardized course installer is handled by the caller.
enter_course() {
  echo "ENTERING COURSE"
  local course="$1"
  local cname iname course_workdir
  cname="$(get_container_name "$course")"
  iname="$(get_image_name "$course")"
  course_workdir="$CCC_MOUNT_PATH"
  echo "CCC_MOUNT_PATH=${CCC_MOUNT_PATH:-<unset>}"
  [[ "$course" != "default" ]] && course_workdir="$CCC_MOUNT_PATH/$course"
  echo "testing log"
  check_container_runtime
  log_info "Course: $course"
  show_course_status "$course"
  build_course_image "$course"
  echo "made it there"
  if has_container "$course"; then
    local status
    status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$cname")
    if [[ "$status" != "running" ]]; then
      echo "Starting container '$cname'..."
      "$CONTAINER_RUNTIME" start "$cname"
    fi

    local cmd="cd '$course_workdir' && exec bash"
    echo_and_run "$CONTAINER_RUNTIME" exec -it "$cname" bash -c "$cmd"
  else
    CONTAINER_NAME="$cname"
    IMAGE_NAME="$iname"
    CONTAINER_WORKDIR="$course_workdir"
    start_new_container
  fi
}