#!/bin/bash
set -euo pipefail
# Host mode functionality (from ccc-host.sh)

# Global flags
VERBOSE=false

# Load settings (after utils is loaded)
load_settings

# Container configuration from settings
IMAGE_NAME="$CCC_IMAGE_PREFIX"
CONTAINER_NAME="$CCC_IMAGE_PREFIX-default"
NETWORK_NAME="$CCC_NETWORK_NAME"

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

# Platform detection
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
  PLATFORM="linux/arm64"
  CONTAINERFILE_PATH="$SCRIPT_DIR/Dockerfile.arm64"
else
  PLATFORM="linux/amd64"
  CONTAINERFILE_PATH="$SCRIPT_DIR/Dockerfile.amd64"
fi

# Registry file location
REGISTRY_FILE="$SCRIPT_DIR/registry.csv"

# Container runtime configuration (will be set after settings are loaded)
CONTAINER_RUNTIME="podman"

# Host initialization
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
  create_default_settings

  echo "Configuration saved to: $(get_config_file)"
  echo "Settings file created at: $(get_settings_file)"
  echo "Setup complete! You can now run 'ccc setup <course>' to install courses."
  echo "You can run 'ccc run <course>' to start a container."
}

# Host usage
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

# Host main function
host_main() {
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
    delegate_to_container "update" "$course"
    exit 0
  fi

  # ccc upgrade
  if [[ "$#" -eq 1 && "$1" == "upgrade" ]]; then
    update_self
    exit 0
  fi

  # Container commands (load container library when needed)
  if [[ "$1" == "build" || "$1" == "run" || "$1" == "clean" || "$1" == "status" ]]; then
    source_lib "container"
  fi

  if [[ "$#" -eq 1 && "$1" == "build" ]]; then
    check_container_runtime
    log_info "Checking container status..."
    show_container_status
    log_info "Building container image..."
    build_image "$CCC_DEFAULT_BASE_IMAGE" "$CCC_IMAGE_PREFIX"
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
