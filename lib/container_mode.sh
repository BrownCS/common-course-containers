#!/bin/bash
set -euo pipefail
# Container mode functionality (from ccc-container.sh)

# Container-specific settings
BASE_DIR="${CCC_COURSES_BASE_DIR:-/courses}"

# Container-specific function for compatibility
get_base_dir() {
  echo "$BASE_DIR"
}

# Settings are passed as environment variables from host
# Set defaults in case environment variables are not provided
CCC_IMAGE_PREFIX="${CCC_IMAGE_PREFIX:-ccc}"
CCC_NETWORK_NAME="${CCC_NETWORK_NAME:-net-ccc}"
CCC_DEFAULT_BASE_IMAGE="${CCC_DEFAULT_BASE_IMAGE:-ubuntu:noble}"
CCC_MOUNT_PATH="${CCC_MOUNT_PATH:-/courses}"
CCC_UPDATE_REPO="${CCC_UPDATE_REPO:-BrownCS/common-course-containers}"

# Derive dependent values
CCC_UPDATE_API_URL="https://api.github.com/repos/$CCC_UPDATE_REPO/releases/latest"

# Registry file location
REGISTRY_FILE="$SCRIPT_DIR/registry.csv"

# Container initialization
init() {
  # Base directory should exist and be mounted
  if [[ ! -d "$BASE_DIR" ]]; then
    echo_error "Courses directory does not exist: $BASE_DIR"
    echo "This script should be run inside the container where $BASE_DIR is mounted"
    exit 1
  fi

  # Check if it's mounted (container-specific check)
  if ! mountpoint -q "$BASE_DIR" 2>/dev/null; then
    echo_error "$BASE_DIR is not a mountpoint. Are you running inside the container?"
    exit 1
  fi
}

# Container usage
usage() {
  echo "Usage ccc:"
  echo "Course Commands:"
  echo "  setup <course>      Clone and run course setup"
  echo "  list                List downloaded courses"
  echo "  update <basename>   Update course repository to latest version"
  echo "  run <course>        Switch to course container (shows help)"
  echo "  upgrade             Upgrade ccc tool to latest version"
  echo ""
  list_available_courses
  echo ""
  echo "Example: ccc setup csci-0300-demo"
  exit 0
}

# Container main function
container_main() {
  # For all commands, check that we're in container environment
  init

  # ccc list
  if [[ "$#" -eq 1 && ("$1" == "list" || "$1" == "ls") ]]; then
    list_courses
    exit 0
  fi

  # ccc setup <course>
  if [[ "$#" -eq 2 && ("$1" == "setup" || "$1" == "s") ]]; then
    setup_course "$2"
    exit 0
  fi

  # ccc update <course>
  if [[ "$#" -eq 2 && "$1" == "update" ]]; then
    upgrade_course "$2"
    exit 0
  fi

  # ccc upgrade
  if [[ "$#" -eq 1 && "$1" == "upgrade" ]]; then
    update_self
    exit 0
  fi

  # ccc run <course> - container switching
  if [[ "$#" -eq 2 && "$1" == "run" ]]; then
    handle_container_switching "$2"
    exit 0
  fi

  if [[ "$#" -ge 1 ]]; then
    echo_error "Invalid command: $*"
  fi

  usage
}