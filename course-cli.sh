#!/usr/bin/env bash

set -e

# Configuration
REPO_BASE_DIR="/home/courses"

declare -A COURSE_REPOS=(
  ["300"]="https://github.com/csci0300/cs300-s24-devenv.git"
)

usage() {
  echo "Usage: $0 setup <course-name>"
  echo "Available courses:"
  for course in $(printf "%s\n" "${!COURSE_REPOS[@]}" | sort); do
    echo "  - $course"
  done
  exit 1
}

clone_or_update_repo() {
  local course=$1
  local repo_url=${COURSE_REPOS[$course]}
  local course_dir="$REPO_BASE_DIR/$course"

  if [[ -z "$repo_url" ]]; then
    echo "Error: Unknown course '$course'"
    exit 1
  fi

  if [[ -d "$course_dir/.git" ]]; then
    echo "Updating $course repo..."
    git -C "$course_dir" pull
  else
    echo "Cloning $course repo..."
    mkdir -p "$REPO_BASE_DIR"
    git clone "$repo_url" "$course_dir"
  fi
}

run_setup_script() {
  local course=$1
  local course_dir="$REPO_BASE_DIR/$course"
  local script="$course_dir/setup.sh"

  if [[ ! -f "$script" ]]; then
    echo "Error: No setup.sh found in $course_dir"
    exit 1
  fi

  echo "Running setup for $course..."
  chmod +x "$script"
  "$script"
}

main() {
  if [[ "$#" -ne 2 || "$1" != "setup" ]]; then
    usage
  fi

  local course="$2"

  clone_or_update_repo "$course"
  run_setup_script "$course"
}

main "$@"
