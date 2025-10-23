#!/usr/bin/env bash
set -euo pipefail

# VERSION is loaded from lib/utils.sh get_version() function

# Global flags
VERBOSE=false

# Script directory - use installed location when available
if [[ -d "$HOME/.local/share/ccc" ]]; then
  SCRIPT_DIR="$HOME/.local/share/ccc"
elif [[ -d "/usr/local/share/ccc" ]]; then
  SCRIPT_DIR="/usr/local/share/ccc"
else
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
fi

# Get courses directory from configuration
get_base_dir() {
  # Check if explicitly set via environment variable
  if [[ -n "${CCC_COURSES_DIR:-}" ]]; then
    echo "$CCC_COURSES_DIR"
    return
  fi

  # Load from configuration file
  local courses_dir="$(load_courses_dir)"
  if [[ -n "$courses_dir" ]]; then
    echo "$courses_dir"
    return
  fi

  # No configuration found
  echo_error "No courses directory configured"
  echo "Run 'ccc init' in the directory where you want to store courses"
  echo "Current config file: $(get_config_file)"
  exit 1
}

# Self-update (now handled by install.sh via update_self function)
SELF="$(realpath "$0")"

# Container configuration (from run-podman)
IMAGE_NAME="ccc"
CONTAINER_NAME="ccc-default"
CONTAINER_RUNTIME="podman"
# VOLUME_PATH will be set in main() after libraries are loaded
NETWORK_NAME="net-ccc"
ARCH="$(uname -m)"

# Platform detection
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
  PLATFORM="linux/arm64"
  CONTAINERFILE_PATH="$SCRIPT_DIR/Dockerfile.arm64"
else
  PLATFORM="linux/amd64"
  CONTAINERFILE_PATH="$SCRIPT_DIR/Dockerfile.amd64"
fi

# Registry file location
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

# Note: Container lib will be loaded conditionally later

# Registry and course functions loaded from lib/courses.sh

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

# Host script - assumes always running on host
# No environment detection needed

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

# Execute commands inside container
delegate_to_container() {
  # TODO: This function has error handling issues that need to be addressed:
  # 1. Error messages from container scripts can get swallowed or not displayed properly
  # 2. Exit codes are captured but stdout/stderr buffering can hide error messages
  # 3. The --interactive --tty flags were added to help but may cause issues in non-interactive environments
  # 4. Consider redesigning to have better error propagation or move more validation to host
  local command="$1"
  shift
  local args="$@"

  # Extract course for course-specific commands
  local course=""
  if [[ "$command" == "setup" || "$command" == "s" ]] && [[ -n "$1" ]]; then
    course="$1"
  fi

  local image_name="$(get_image_name "$course")"

  # Ensure network and image exist
  create_network
  build_image_for_course "$course"

  # Run command in temporary container with proper user setup
  "$CONTAINER_RUNTIME" run --rm \
    --interactive \  # TODO: May cause issues in non-interactive environments (CI/CD)
    --tty \          # TODO: May cause issues when no TTY available
    --userns keep-id:uid=$(id -u),gid=$(id -g) \
    --platform "$PLATFORM" \
    --network "${NETWORK_NAME}" \
    --privileged \
    --volume "$VOLUME_PATH":/courses \
    --workdir /courses \
    --env CCC_COURSES_BASE_DIR=/courses \
    --env DIRENV_CONFIG=/root/.config/direnv \
    "$image_name" \
    ccc $([ "$VERBOSE" = "true" ] && echo "--verbose") "$command" $args
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    exit $exit_code
  fi
}

init() {
  local courses_dir="$(get_base_dir)"

  # Check if courses directory exists
  if [[ ! -d "$courses_dir" ]]; then
    echo_error "Courses directory does not exist: $courses_dir"
    echo "Run 'ccc init' to set up your courses directory"
    exit 1
  fi

  # Only check for mountpoint if we're likely in a container context
  if [[ "$courses_dir" == "/home/"*"/courses" ]] && ! mountpoint -q "$courses_dir" 2>/dev/null; then
    echo_error "$courses_dir is not a mountpoint. Are you running inside the container?"
    echo "If you're on the host, try: ccc run"
    exit 1
  fi
}

init_courses_dir() {
  local courses_dir="$(pwd)/courses"

  echo "Setting up courses directory at: $courses_dir"

  if [[ ! -d "$courses_dir" ]]; then
    mkdir -p "$courses_dir"
    echo "Created courses directory: $courses_dir"
  else
    echo "Using existing directory: $courses_dir"
  fi

  save_courses_dir "$courses_dir"

  echo "Configuration saved to: $(get_config_file)"
  echo "Setup complete! You can now run 'ccc setup <course>' to install courses."
  echo "You can run 'ccc run <course>' to start a container."
}

# Usage - host context only
usage() {
  echo "Usage: $0 [OPTIONS] COMMAND [ARGS...]"
  echo ""
  echo "Global Options:"
  echo "  --verbose, -v       Show detailed output"
  echo "  --version           Show version"
  echo "  --help, -h          Show this help"
  echo ""
  echo "Container Commands:"
  echo "  build               Build container image"
  echo "  run <course>        Start/attach to course-specific container"
  echo "  clean [all|containers|images|networks]  Clean resources"
  echo "  status              Show container status"
  echo ""
  echo "Course Commands (delegates to container):"
  echo "  setup <course>      Setup course (starts container if needed)"
  echo "  list                List courses (from container)"
  echo "  update <course>     Update course repository (in container)"
  echo ""
  echo "Utility Commands:"
  echo "  init                Setup courses directory"
  echo "  config              Show current configuration"
  echo "  config set-courses-dir <path>  Change courses directory"
  echo "  upgrade             Upgrade ccc tool itself"
  echo ""
  list_available_courses
  echo ""
  echo "Examples:"
  echo "  $0 setup csci-0300-demo"
  echo "  $0 run csci-0300-demo"
  exit 0
}

# Load container management functions (always needed on host)
source_lib "container"

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
    build_image "ubuntu:noble" "$image_name"
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
  local course_workdir="/courses"
  if [[ "$course" != "default" && -d "$VOLUME_PATH/$course" ]]; then
    course_workdir="/courses/$course"
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

main() {
  # Parse global flags first
  while [[ $# -gt 0 ]]; do
    case $1 in
    --verbose | -v)
      VERBOSE=true
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    --version)
      echo "ccc $(get_version)"
      exit 0
      ;;
    *)
      # Not a global flag, break and continue with command parsing
      break
      ;;
    esac
  done

  # ccc init - setup courses directory (works without configuration)
  if [[ "$#" -eq 1 && "$1" == "init" ]]; then
    init_courses_dir
    exit 0
  fi

  # Set VOLUME_PATH for commands that need it
  VOLUME_PATH="$(get_base_dir)"

  # ccc config - show/modify configuration
  if [[ "$#" -eq 1 && "$1" == "config" ]]; then
    if has_courses_config; then
      echo "Courses directory: $(load_courses_dir)"
      echo "Config file: $(get_config_file)"
    else
      echo "No configuration found. Run 'ccc init' to set up."
    fi
    exit 0
  fi

  if [[ "$#" -eq 3 && "$1" == "config" && "$2" == "set-courses-dir" ]]; then
    local new_dir="$3"
    if [[ ! -d "$new_dir" ]]; then
      echo_error "Directory does not exist: $new_dir"
      exit 1
    fi
    save_courses_dir "$new_dir"
    echo "Courses directory updated to: $(realpath "$new_dir")"
    echo "Config file: $(get_config_file)"
    exit 0
  fi

  # For all other commands, check that environment is set up
  init

  # ccc setup <course> - validate then delegate to container
  if [[ "$#" -eq 2 && ("$1" == "setup" || "$1" == "s") ]]; then
    local course="$2"
    # Validate course exists in registry (allow default even with empty URL)
    if [[ "$course" != "default" ]] && ! get_course_url "$course" >/dev/null 2>&1; then
      log_error "Course '$course' not found in registry"
      list_available_courses
      exit 1
    fi
    # TODO: delegate_to_container should properly propagate all error messages and exit codes
    # Currently errors from container scripts can get swallowed or not displayed properly
    delegate_to_container "setup" "$course"
    exit 0
  fi

  # ccc list - show installed courses (no container needed)
  if [[ "$#" -eq 1 && ("$1" == "list" || "$1" == "ls") ]]; then
    list_courses
    exit 0
  fi

  # ccc update <course> - validate then delegate to container
  if [[ "$#" -eq 2 && "$1" == "update" ]]; then
    local course="$2"
    # Validate course exists in registry
    if ! get_course_url "$course" >/dev/null 2>&1; then
      log_error "Course '$course' not found in registry"
      list_available_courses
      exit 1
    fi
    # TODO: delegate_to_container should properly propagate all error messages and exit codes
    # Currently errors from container scripts can get swallowed or not displayed properly
    delegate_to_container "update" "$course"
    exit 0
  fi

  # ccc upgrade
  if [[ "$#" -eq 1 && "$1" == "upgrade" ]]; then
    update_self
    exit 0
  fi

  # Container commands
  if [[ "$#" -eq 1 && "$1" == "build" ]]; then
    check_container_runtime
    log_info "Checking container status..."
    show_container_status
    log_info "Building container image..."
    build_image "ubuntu:noble" "ccc"
    log_success "Image build completed"
    exit 0
  fi

  if [[ "$#" -eq 2 && "$1" == "run" ]]; then
    local course="$2"
    # Validate course exists in registry (allow default even with empty URL)
    if [[ "$course" != "default" ]] && ! get_course_url "$course" >/dev/null 2>&1; then
      log_error "Course '$course' not found in registry"
      list_available_courses
      exit 1
    fi

    # Check if course has been set up locally (except for default)
    if [[ "$course" != "default" ]] && [[ ! -d "$VOLUME_PATH/$course" ]]; then
      log_error "Course '$course' not set up locally"
      echo "Run 'ccc setup $course' first to download course content"
      exit 1
    fi

    check_container_runtime
    log_info "Checking container status for course: $course"
    show_container_status_for_course "$course"
    log_info "Ensuring image is available for course: $course"
    build_image_for_course "$course"
    log_info "Starting container for course: $course"
    run_container_for_course "$course"
    exit 0
  fi

  # Clean commands
  if [[ "$#" -eq 2 && "$1" == "clean" ]]; then
    check_container_runtime
    case "$2" in
    containers)
      remove_containers
      ;;
    images)
      remove_image
      ;;
    networks)
      remove_network
      ;;
    all)
      remove_containers
      remove_image
      remove_network
      ;;
    *)
      log_error "Invalid clean option: $2"
      echo "Valid options: containers, images, networks, all"
      exit 1
      ;;
    esac
    exit 0
  fi

  # Legacy clean command (clean all)
  if [[ "$#" -eq 1 && "$1" == "clean" ]]; then
    check_container_runtime
    remove_containers
    remove_image
    remove_network
    exit 0
  fi

  if [[ "$#" -eq 1 && "$1" == "status" ]]; then
    show_container_status
    exit 0
  fi

  if [[ "$#" -ge 1 ]]; then
    log_error "Invalid command: $*"
  fi

  usage
}

main "$@"
