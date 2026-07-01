#!/bin/bash
set -euo pipefail

# Host mode: CLI dispatch when running on the host machine

VERBOSE=false
IMAGE_NAME="$CCC_IMAGE_PREFIX"
CONTAINER_NAME="$CCC_IMAGE_PREFIX-default"
NETWORK_NAME="$CCC_NETWORK_NAME"
REGISTRY_FILE="$SCRIPT_DIR/registry.csv"
CONTAINER_RUNTIME="podman"

# Load shared mode helpers
if [[ -f "$SCRIPT_DIR/lib/mode_helpers.sh" ]]; then
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/lib/mode_helpers.sh"
  detect_arch_platform
else
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    PLATFORM="linux/arm64"
  else
    PLATFORM="linux/amd64"
  fi
fi

get_base_dir() {
  mode_get_base_dir_host || exit 1
}

init() {
  local courses_dir
  courses_dir="$(get_base_dir)"
  mode_init_host "$courses_dir" || exit 1
}

init_courses_dir() {
  local courses_dir="$(pwd)/courses"
  echo "Setting up courses directory at: $courses_dir"
  mkdir -p "$courses_dir"
  save_courses_dir "$courses_dir"
  create_default_settings
  echo "Configuration saved to: $(get_config_file)"
  echo "Setup complete! You can now run 'ccc setup <course>' to install courses."
}

validate_course() {
  local course="$1"
  if [[ "$course" != "default" ]] && ! get_course_url "$course" >/dev/null 2>&1; then
    log_error "Course '$course' not found in registry"
    list_available_courses
    exit 1
  fi
}

usage() {
  echo "Usage: $0 [OPTIONS] COMMAND [ARGS...]"
  echo ""
  echo "Options:"
  echo "  --verbose, -v       Show detailed output"
  echo "  --version           Show version"
  echo "  --help, -h          Show this help"
  echo ""
  echo "Commands:"
  echo "  init                Setup courses directory"
  echo "  setup <course>      Setup course"
  echo "  run [course]        Start/attach to container (default: default)"
  echo "  list                List courses"
  echo "  update <course>     Update course repository"
  echo "  build               Build container image"
  echo "  clean [target]      Clean resources (containers|images|networks|all)"
  echo "  status              Show container status"
  echo "  config              Show current configuration"
  echo "  upgrade             Upgrade ccc tool itself"
  echo ""
  list_available_courses
  echo ""
  echo "Examples:"
  echo "  $0 setup csci-0300-demo"
  echo "  $0 run csci-0300-demo"
  exit 0
}

host_main() {
  # Parse global flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose|-v) VERBOSE=true; shift ;;
      --help|-h)    usage ;;
      --version)    echo "ccc $(get_version)"; exit 0 ;;
      *)            break ;;
    esac
  done

  if [[ "$#" -eq 0 ]]; then
    usage
  fi

  local cmd="$1"
  shift

  # 'init' works without existing configuration
  if [[ "$cmd" == "init" ]]; then
    init_courses_dir
    exit 0
  fi

  # Set VOLUME_PATH from configuration
  if ! VOLUME_PATH="$(get_base_dir 2>&1)"; then
    echo "$VOLUME_PATH" >&2
    exit 1
  fi

  # 'config' doesn't need full initialization
  if [[ "$cmd" == "config" ]]; then
    if [[ "$#" -eq 2 && "$1" == "set-courses-dir" ]]; then
      if [[ ! -d "$2" ]]; then
        echo_error "Directory does not exist: $2"
        exit 1
      fi
      save_courses_dir "$2"
      echo "Courses directory updated to: $(realpath "$2")"
    elif [[ "$#" -eq 0 ]]; then
      if has_courses_config; then
        echo "Courses directory: $(load_courses_dir)"
        echo "Config file: $(get_config_file)"
      else
        echo "No configuration found. Run 'ccc init' to set up."
      fi
    fi
    exit 0
  fi

  # All remaining commands need the courses directory to exist
  init

  case "$cmd" in
    setup|s)
      [[ "$#" -ne 1 ]] && { log_error "Usage: ccc setup <course>"; exit 1; }
      validate_course "$1"
      clone_course "$1" "$VOLUME_PATH"
      enter_course "$1" --setup
      ;;

    list|ls)
      list_courses
      ;;

    update)
      [[ "$#" -ne 1 ]] && { log_error "Usage: ccc update <course>"; exit 1; }
      validate_course "$1"
      upgrade_course "$1"
      ;;

    upgrade)
      update_self
      ;;

    build)
      check_container_runtime
      show_course_status
      build_image "$CCC_DEFAULT_BASE_IMAGE" "$CCC_IMAGE_PREFIX"
      log_success "Image build completed"
      ;;

    run)
      local course="${1:-default}"
      validate_course "$course"
      if [[ "$course" != "default" ]] && [[ ! -d "$VOLUME_PATH/$course" ]]; then
        log_error "Course '$course' not set up locally"
        echo "Run 'ccc setup $course' first to download course content"
        exit 1
      fi
      enter_course "$course"
      ;;

    clean)
      check_container_runtime
      case "${1:-all}" in
        containers) remove_containers ;;
        images)     remove_image ;;
        networks)   remove_network ;;
        all)        remove_containers; remove_image; remove_network ;;
        *)          log_error "Invalid clean option: $1"; exit 1 ;;
      esac
      ;;

    status)
      check_container_runtime
      show_course_status
      ;;

    *)
      log_error "Invalid command: $cmd"
      usage
      ;;
  esac

  exit 0
}
