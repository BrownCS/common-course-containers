#!/usr/bin/env bash
set -euo pipefail

# CCC Container Script - Course Management Only
# This runs inside the container and provides course management commands

# VERSION is loaded from lib/utils.sh get_version() function
BASE_DIR="${CCC_COURSES_BASE_DIR:-/courses}"

# Container-specific function for compatibility with shared libs
get_base_dir() {
  echo "$BASE_DIR"
}

# Self-update (now handled by install.sh via update_self function)
SELF="$(realpath "$0")"

# Registry file location
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REGISTRY_FILE="$SCRIPT_DIR/registry.csv"

# Load library functions
source_lib() {
  local lib="$1"
  local lib_file="$SCRIPT_DIR/lib/$lib.sh"

  if [[ -f "$lib_file" ]]; then
    source "$lib_file"
  else
    echo "ERROR: Library file not found: $lib_file" >&2
    exit 1
  fi
}

# Load shared libraries
source_lib "utils"
source_lib "courses"

# Course and utility functions loaded from shared libraries

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

# All course management and utility functions moved to shared libraries

# Usage - container context only
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

main() {
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

main "$@"
