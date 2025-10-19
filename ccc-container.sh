#!/usr/bin/env bash

# CCC Container Script - Course Management Only
# This runs inside the container and provides course management commands

VERSION="1.0.5"
BASE_DIR="/home/courses"

# Self-update
SELF="$(realpath "$0")"
REMOTE_SELF="https://raw.githubusercontent.com/BrownCS/common-course-containers/main/ccc-container.sh"

# Registry file location
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REGISTRY_FILE="$SCRIPT_DIR/registry.csv"

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

# Course utilities
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

# Usage - container context only
usage() {
  echo "Usage ccc:"
  echo "Course Commands:"
  echo "  setup <course>      Clone and run course setup"
  echo "  list                List downloaded courses"
  echo "  upgrade <basename>  Upgrade course to the latest version"
  echo "  update              Update ccc to the latest version"
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

  # ccc upgrade <course>
  if [[ "$#" -eq 2 && "$1" == "upgrade" ]]; then
    upgrade_course "$2"
    exit 0
  fi

  # ccc update
  if [[ "$#" -eq 1 && "$1" == "update" ]]; then
    update_self
    exit 0
  fi

  if [[ "$#" -ge 1 ]]; then
    echo "ERROR: Invalid command: $*"
  fi

  usage
}

main "$@"