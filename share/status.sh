#!/bin/bash
set -euo pipefail

# Course and container status inspection
# Functions:
#  - show_default_container_status
#  - show_course_status
#  - ccc_status (dispatcher)

show_default_container_status() {
  local default_image="ccc"
  local default_container="default"

  CONTAINER_RUNTIME=$(detect_container_runtime 2>/dev/null || true)
  if [ -z "${CONTAINER_RUNTIME:-}" ]; then
    echo "Container runtime not detected." >&2
    return 1
  fi

  echo "Default container: $default_container"
  echo "  Image: $default_image"

  # Direct checks for known default names (bypass course-aware naming logic)
  if "$CONTAINER_RUNTIME" image exists "$default_image" &>/dev/null; then
    echo "    Built: yes"
  else
    echo "    Built: no"
  fi

  if "$CONTAINER_RUNTIME" container exists "$default_container" &>/dev/null; then
    local container_status
    container_status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$default_container" 2>/dev/null || echo "unknown")
    echo "  Container status: $container_status"
  else
    echo "  Container status: not created"
  fi

  # Show which courses use the default container
  local default_courses
  default_courses="$(list_default_container_courses 2>/dev/null || true)"
  if [ -n "$default_courses" ]; then
    echo "  Used by:"
    while IFS= read -r course_id; do
      [ -n "$course_id" ] && echo "    - $course_id"
    done <<< "$default_courses"
  else
    echo "  Used by: (none)"
  fi
}

show_course_status() {
  local course_id="$1"
  local course_dir="${CCC_COURSES_DIR:-$HOME/courses}/$course_id"
  local image_mode
  local container_name
  local image_name

  image_mode="$(get_course_image_mode "$course_id" 2>/dev/null || echo "default")"
  container_name="$(get_container_name "$course_id")"
  image_name="$(get_image_name "$course_id")"

  CONTAINER_RUNTIME=$(detect_container_runtime 2>/dev/null || true)
  if [ -z "${CONTAINER_RUNTIME:-}" ]; then
    echo "Container runtime not detected." >&2
    return 1
  fi

  echo "Course: $course_id"
  echo "  Image mode: $image_mode"

  # Repository status
  if [ -d "$course_dir/.git" ]; then
    local branch current_commit
    branch=$(cd "$course_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    current_commit=$(cd "$course_dir" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "  Repository: $course_dir (checked out on $branch)"
    echo "    Commit: $current_commit"
  elif [ -d "$course_dir" ]; then
    echo "  Repository: $course_dir (checked out, not a git repo)"
  else
    echo "  Repository: not checked out"
  fi

  # Image status
  echo "  Image: $image_name"
  if "$CONTAINER_RUNTIME" image exists "$image_name" &>/dev/null; then
    local image_created
    image_created=$($CONTAINER_RUNTIME inspect -f '{{.Created}}' "$image_name" 2>/dev/null || echo "unknown")
    echo "    Built: yes (created $image_created)"
  else
    echo "    Built: no"
  fi

  # Container status
  echo "  Container: $container_name"
  if "$CONTAINER_RUNTIME" container exists "$container_name" &>/dev/null; then
    local container_status
    container_status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
    echo "    Status: $container_status"
  else
    echo "    Status: not created"
  fi
}

ccc_status() {
  local course_id="${1:-}"

  if [ -z "$course_id" ]; then
    # Show default container status
    show_default_container_status
  else
    # Show specific course status
    ensure_course_exists "$course_id" || return 1
    show_course_status "$course_id"
  fi
}
