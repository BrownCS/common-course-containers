#!/bin/bash
set -euo pipefail

# Course and registry management utilities

require_registry_file() {
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo_error "Registry file not found: $REGISTRY_FILE"
    return 1
  fi
}

get_course_info() {
  local course="$1"
  local field="${2:-url}"  # url, name, semester, requires_container, image_mode, image_ref, container_arch, default_branch, notes, or all

  require_registry_file || return 1

  # Parse CSV, skip comments and empty lines
  while IFS=',' read -r course_id repo_url name semester requires_container image_mode image_ref container_arch default_branch notes; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue

    if [[ "$course_id" == "$course" ]]; then
      case "$field" in
        url) echo "$repo_url" ;;
        name) echo "$name" ;;
        semester) echo "$semester" ;;
        requires_container) echo "${requires_container:-true}" ;;
        image_mode) echo "${image_mode:-default}" ;;
        image_ref) echo "${image_ref:-}" ;;
        container_arch) echo "${container_arch:-}" ;;
        default_branch) echo "${default_branch:-}" ;;
        notes) echo "${notes:-}" ;;
        all) echo "$course_id,$repo_url,$name,$semester,${requires_container:-true},${image_mode:-default},${image_ref:-},${container_arch:-},${default_branch:-},${notes:-}" ;;
        *) echo_error "Invalid field: $field"; return 1 ;;
      esac
      return 0
    fi
  done < "$REGISTRY_FILE"

  return 1
}

get_course_requires_container() {
  get_course_info "$1" "requires_container"
}

get_course_image_mode() {
  get_course_info "$1" "image_mode"
}

get_course_image_ref() {
  get_course_info "$1" "image_ref"
}

get_course_container_arch() {
  get_course_info "$1" "container_arch"
}

get_course_container_platform() {
  local arch
  arch="$(get_course_container_arch "$1")" || arch=""
  case "$arch" in
    arm64|amd64)
      echo "linux/$arch"
      ;;
    linux/arm64|linux/amd64)
      echo "$arch"
      ;;
    *)
      case "$(uname -m)" in
        arm64|aarch64) echo "linux/arm64" ;;
        *) echo "linux/amd64" ;;
      esac
      ;;
  esac
}

get_course_build_base_image() {
  local mode ref
  mode="$(get_course_image_mode "$1")" || mode="default"
  ref="$(get_course_image_ref "$1")" || ref=""
  if [[ "$mode" == "course-specific" && -n "$ref" ]]; then
    echo "$ref"
  elif [[ "$mode" == "course-specific" ]]; then
    echo_error "Course-specific image requested for '$1' but no image_ref was set in the registry"
    return 1
  else
    echo "$CCC_DEFAULT_BASE_IMAGE"
  fi
}

ensure_course_exists() {
  local course="$1"
  if [[ -z "$course" ]]; then
    echo_error "No course specified"
    list_available_courses
    return 1
  fi

  if ! get_course_info "$course" "url" >/dev/null 2>&1; then
    echo_error "Course '$course' not found in registry"
    list_available_courses
    return 1
  fi
}

list_available_courses() {
  require_registry_file || return 1

  echo "Available courses:"
  while IFS=',' read -r course_id repo_url name semester requires_container image_mode image_ref container_arch default_branch notes; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue
    echo "  $course_id"
  done < "$REGISTRY_FILE"
}

