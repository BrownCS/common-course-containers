#!/bin/bash
set -euo pipefail

# Mode helper utilities: shared functions for host/container mode scripts.

# Detect architecture and set ARCH and PLATFORM variables
detect_arch_platform() {
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    PLATFORM="linux/arm64"
  else
    PLATFORM="linux/amd64"
  fi
  export ARCH PLATFORM
}

# Host-side: resolve courses directory from env or saved config
mode_get_base_dir_host() {
  if [[ -n "${CCC_COURSES_DIR:-}" ]]; then
    echo "$CCC_COURSES_DIR"
    return
  fi

  local courses_dir
  courses_dir="$(load_courses_dir)" || true
  if [[ -n "$courses_dir" ]]; then
    echo "$courses_dir"
    return
  fi

  echo_error "No courses directory configured"
  echo "Run 'ccc init' in the directory where you want to store courses"
  echo "Current config file: $(get_config_file)"
  return 1
}

# Host-side initialization checks for courses directory
# accepts one arg: courses_dir
mode_init_host() {
  local courses_dir="${1:-}"
  if [[ -z "$courses_dir" ]]; then
    echo_error "Internal error: mode_init_host called without courses_dir"
    return 1
  fi

  if [[ ! -d "$courses_dir" ]]; then
    echo_error "Courses directory does not exist: $courses_dir"
    echo "Run 'ccc init' to set up your courses directory"
    return 1
  fi

  # If this looks like a host path that should be a mountpoint, warn if not mounted
  if [[ "$courses_dir" == "/home/"*"/courses" ]] && ! mountpoint -q "$courses_dir" 2>/dev/null; then
    echo_error "$courses_dir is not a mountpoint. Are you running inside the container?"
    echo "If you're on the host, try: ccc run"
    return 1
  fi
}

# Container-side: simple base dir getter (container sets BASE_DIR env)
mode_get_base_dir_container() {
  echo "${BASE_DIR:-/courses}"
}

# Container-side initialization: ensure BASE_DIR exists and is a mountpoint
mode_init_container() {
  local base_dir="${BASE_DIR:-/courses}"
  if [[ ! -d "$base_dir" ]]; then
    echo_error "Courses directory does not exist: $base_dir"
    echo "This script should be run inside the container where $base_dir is mounted"
    return 1
  fi

  if ! mountpoint -q "$base_dir" 2>/dev/null; then
    echo_error "$base_dir is not a mountpoint. Are you running inside the container?"
    return 1
  fi
}

## End mode_helpers
