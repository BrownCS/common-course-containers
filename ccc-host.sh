#!/usr/bin/env bash

VERSION="1.0.5"

# Determine base directory based on context
get_base_dir() {
  # Check if explicitly set
  if [[ -n "$CCC_COURSES_DIR" ]]; then
    echo "$CCC_COURSES_DIR"
    return
  fi

  # Auto-detect based on likely container environment
  if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || [[ -d "/home/courses" ]]; then
    echo "/home/courses"
  else
    echo "./courses"
  fi
}

BASE_DIR="$(get_base_dir)"

# Self-update
SELF="$(realpath "$0")"
REMOTE_SELF="https://raw.githubusercontent.com/BrownCS/common-course-containers/main/ccc.sh"

# Container configuration (from run-podman)
IMAGE_NAME="cs-courses"
CONTAINER_NAME="cs-courses"
CONTAINER_RUNTIME="podman"
VOLUME_PATH="$SCRIPT_DIR/courses"
NETWORK_NAME="net-cs-courses"
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
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REGISTRY_FILE="$SCRIPT_DIR/registry.csv"

# Load library functions
source_lib() {
  local lib="$1"
  local lib_file="$SCRIPT_DIR/lib/$lib.sh"

  if [[ -f "$lib_file" ]]; then
    source "$lib_file"
  else
    echo_error "Library file not found: $lib_file"
    exit 1
  fi
}

# Note: Container lib will be loaded conditionally later

# Registry functions (CSV-based, bash 3.2+ compatible)
get_course_url() {
  local course="$1"

  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo_error "Registry file not found: $REGISTRY_FILE"
    return 1
  fi

  # Parse CSV, skip comments and empty lines
  while IFS=',' read -r course_id repo_url name semester; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue

    if [[ "$course_id" == "$course" ]]; then
      echo "$repo_url"
      return 0
    fi
  done < "$REGISTRY_FILE"

  return 1
}

list_available_courses() {
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo_error "Registry file not found: $REGISTRY_FILE"
    return 1
  fi

  echo "Available courses:"
  while IFS=',' read -r course_id repo_url name semester; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue
    echo "  $course_id"
  done < "$REGISTRY_FILE"
}

# Host script - assumes always running on host
# No environment detection needed

# Basic container management functions
check_container_runtime() {
  if command -v "$CONTAINER_RUNTIME" >/dev/null; then
    return 0
  fi

  # Check if they have docker instead
  if command -v docker >/dev/null; then
    echo_error "Found Docker but this system requires Podman"
    echo "Please install Podman: https://podman.io/getting-started/installation"
    echo "Docker is not compatible with this course container system."
  else
    echo_error "Container runtime '$CONTAINER_RUNTIME' not found"
    echo "Please install Podman: https://podman.io/getting-started/installation"
  fi

  exit 1
}

has_container() {
  "$CONTAINER_RUNTIME" container exists "$CONTAINER_NAME" &>/dev/null
}

has_image() {
  "$CONTAINER_RUNTIME" image exists "$IMAGE_NAME" &>/dev/null
}

# Smart delegation - execute course commands in container
delegate_to_container() {
  local command="$1"
  shift
  local args="$@"

  # Ensure container is running
  if ! has_container; then
    echo "Container not found. Building and starting..."
    build_image
    # Start container in detached mode for command execution
    if ! [[ -d courses ]]; then
      mkdir courses
    fi
    echo_and_run "$CONTAINER_RUNTIME" run -d \
      --name "$CONTAINER_NAME" \
      --platform "$PLATFORM" \
      --network "${NETWORK_NAME}" \
      --privileged \
      --volume "$VOLUME_PATH":/home/courses \
      --workdir /home/courses \
      "$IMAGE_NAME" sleep infinity
  fi

  # Check if container is running
  local status=$("$CONTAINER_RUNTIME" inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
  if [[ "$status" != "running" ]]; then
    echo "Starting container..."
    "$CONTAINER_RUNTIME" start "$CONTAINER_NAME"
  fi

  # Execute command inside container
  echo "Executing: ccc $command $args"
  "$CONTAINER_RUNTIME" exec "$CONTAINER_NAME" ccc "$command" $args
}

init() {
  # Base directory - create if it doesn't exist
  if [[ ! -d "$BASE_DIR" ]]; then
    echo_error "Courses directory does not exist: $BASE_DIR"
    echo "Run 'ccc init' to set up your courses directory"
    exit 1
  fi

  # Only check for mountpoint if we're likely in a container context
  if [[ "$BASE_DIR" == "/home/courses" ]] && ! mountpoint -q "$BASE_DIR" 2>/dev/null; then
    echo_error "$BASE_DIR is not a mountpoint. Are you running inside the container?"
    echo "If you're on the host, try: ccc run"
    exit 1
  fi
}

init_courses_dir() {
  echo "Setting up courses directory at: $BASE_DIR"

  if [[ -d "$BASE_DIR" ]]; then
    echo "Directory already exists: $BASE_DIR"
  else
    mkdir -p "$BASE_DIR"
    echo "Created courses directory: $BASE_DIR"
  fi

  echo "Setup complete! You can now run 'ccc setup <course>' to install courses."
  echo "You can run 'ccc run' to start the container."
}

setup_course() {
  local course="$1"
  local course_url
  course_url="$(get_course_url "$course")"

  # Get a new name for dirpath
  local dirname="$course"
  local base="$BASE_DIR/$course"
  local dirpath="$base"
  local i=1
  while [[ -e "$dirpath" ]]; do
    dirpath="${base}-$i"
    ((i++))
  done
  local script="$dirpath/setup.sh"

  # Find the course_url
  if [[ $? -ne 0 || -z "$course_url" ]]; then
    echo_error "ERROR: Could not find remote course repository for '$course'"
    echo "(1) To install a course repository manually, run: "
    echo "       git clone <course-url>"
    echo "       chmod +x $script"
    echo "       bash $script"
    echo "(2) To add a new course to ccc, email problem@cs.brown.edu"
    echo "    with the <course> and the <course-url>"
    echo "(3) To modify the course registry locally during development,"
    echo "    edit the registry file at $REGISTRY_FILE"
    list_available_courses
    exit 1
  fi

  # Clone the repository
  echo_and_run git clone "$course_url" "$dirpath"

  # Run the setup script
  if [[ ! -f "$script" ]]; then
    echo_error "ERROR: No setup.sh found in $dirpath"
    echo "       Check with course staff if there should be a setup script for the course"
    return 0
  fi

  echo_and_run chmod +x $script
  echo_and_run bash yes | $script

  # Make sure that direnv is allowed
  if ! grep -q 'direnv hook bash' ~/.bashrc; then
    echo 'eval "$(direnv hook bash)"' >>~/.bashrc
  fi
  cd "$dirpath" && direnv allow
}

list_courses() {
  local tmp=$(mktemp)
  echo "BASENAME,COURSE,COURSE_REPO,COMMIT" >"$tmp"

  for dirpath in "$BASE_DIR"/*; do
    # Check that dirpath is a directory
    [[ -d "$dirpath" ]] || continue

    # Get the course_url
    local course_url
    course_url="$(get_git_url "$dirpath")"
    if [[ "$?" -ne 0 ]]; then continue; fi

    # Find the course
    local course
    course="$(find_course "$course_url")"
    if [[ "$?" -ne 0 ]]; then continue; fi

    # Get the commit
    local commit
    commit="$(get_git_commit "$dirpath")"
    if [[ "$?" -ne 0 ]]; then continue; fi

    local basename="$(basename "$dirpath")"

    echo "$basename,$course,$course_url,$commit" >>"$tmp"
  done

  column -s, -t <"$tmp"
}

upgrade_course() {
  local basename="$1"
  local dirpath="$BASE_DIR/$basename"

  if [[ ! -d "$dirpath" ]]; then
    echo_error "ERROR: '$dirpath' does not exist"
    echo "       Is '$basename' the right directory name?"
    return 1
  fi

  if [[ ! -d "$dirpath/.git" ]]; then
    echo_error "ERROR: $dirpath is not a git repo"
    return 1
  fi

  echo_and_run cd "$dirpath"
  echo_and_run git pull

  # TODO: handle merge conflicts in some way?
}

update_self() {
  echo "Updating to latest version of ccc..."
  tmp=$(mktemp)
  if curl -sSfL "$REMOTE_SELF" -o "$tmp"; then
    if ! cmp -s "$SELF" "$tmp"; then
      chmod +x "$tmp"
      sudo cp "$tmp" "$SELF"
      local new_version
      new_version=$(grep -E '^VERSION=' "$tmp" | cut -d= -f2 | tr -d '"')
      echo "Updated to latest version $new_version"
    else
      echo "Already up to date"
    fi
  else
    echo "Failed to check for update"
  fi
  rm -f "$tmp"
}

# Course utilites

get_git_url() {
  local dirpath="$1"
  local url=$(git -C "$dirpath" remote get-url origin 2>/dev/null)
  if [[ "$?" -ne 0 ]]; then return 1; fi

  if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
    echo "https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    echo "$url"
  fi
}

get_git_commit() {
  local dirpath="$1"
  git -C "$dirpath" rev-parse HEAD 2>/dev/null
}

find_course() {
  local course_url="$1"

  if [[ ! -f "$REGISTRY_FILE" ]]; then
    return 1
  fi

  # Parse CSV to find course by URL
  while IFS=',' read -r course_id repo_url name semester; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue

    if [[ "$repo_url" == "$course_url" ]]; then
      echo "$course_id"
      return 0
    fi
  done < "$REGISTRY_FILE"

  return 1
}

# Printing utilities

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo_and_run() {
  echo -e "${BLUE}$*${RESET}"
  "$@"
}

echo_error() {
  local text="$1"
  echo -e "${RED}${text}${RESET}"
}

# Usage - host context only
usage() {
  echo "Usage $0:"
  echo "Container Commands:"
  echo "  build               Build container image"
  echo "  run                 Start/attach to container"
  echo "  clean               Remove containers and images"
  echo "  status              Show container status"
  echo ""
  echo "Course Commands (delegates to container):"
  echo "  setup <course>      Setup course (starts container if needed)"
  echo "  list                List courses (from container)"
  echo "  upgrade <course>    Upgrade course (in container)"
  echo ""
  echo "Utility Commands:"
  echo "  init                Setup courses directory"
  echo "  update              Update ccc script"
  echo ""
  list_available_courses
  echo ""
  echo "Example: $0 setup csci-0300-demo"
  exit 0
}

# Load container management functions (always needed on host)
source_lib "container"

main() {
  # ccc init - setup courses directory
  if [[ "$#" -eq 1 && "$1" == "init" ]]; then
    init_courses_dir
    exit 0
  fi

  # For all other commands, check that environment is set up
  init

  # ccc setup <course> - delegate to container
  if [[ "$#" -eq 2 && ("$1" == "setup" || "$1" == "s") ]]; then
    delegate_to_container "setup" "$2"
    exit 0
  fi

  # ccc list - delegate to container
  if [[ "$#" -eq 1 && ("$1" == "list" || "$1" == "ls") ]]; then
    delegate_to_container "list"
    exit 0
  fi

  # ccc upgrade <course> - delegate to container
  if [[ "$#" -eq 2 && "$1" == "upgrade" ]]; then
    delegate_to_container "upgrade" "$2"
    exit 0
  fi

  # ccc update
  if [[ "$#" -eq 1 && "$1" == "update" ]]; then
    update_self
    exit 0
  fi

  # Container commands
  if [[ "$#" -eq 1 && "$1" == "build" ]]; then
    check_container_runtime
    show_container_status
    build_image
    exit 0
  fi

  if [[ "$#" -eq 1 && "$1" == "run" ]]; then
    check_container_runtime
    show_container_status
    build_image
    run_container
    exit 0
  fi

  if [[ "$#" -eq 1 && "$1" == "clean" ]]; then
    check_container_runtime
    remove_containers
    remove_image
    exit 0
  fi

  if [[ "$#" -eq 1 && "$1" == "status" ]]; then
    show_container_status
    exit 0
  fi

  if [[ "$#" -ge 1 ]]; then
    echo "ERROR: Invalid command: $*"
  fi

  usage
}

main "$@"
