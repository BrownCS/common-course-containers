#!/usr/bin/env bash

set -e

# Configuration
BASE_DIR="/home/courses"
COURSE_FILE="$BASE_DIR/courses.json"
REMOTE_COURSE_FILE="https://raw.githubusercontent.com/qiaochloe/unified-containers/courses/courses/courses.json"

# Downlaod courses.json from the remote repository
# and save it in COURSE_FILE
download_courses_json() {
  curl -sSfL "$REMOTE_COURSE_FILE" -o "$COURSE_FILE"
}

# Given a course key, get the course URL from COURSE_FILE
get_course_url() {
  local course="$1"
  jq -r --arg course "$course" '.[$course] // empty' "$COURSE_FILE"
}

# List courses in COURSE_FILE
list_courses() {
  echo "Available courses:"
  jq -r 'keys_unsorted[]' "$COURSE_FILE" | sort | sed 's/^/  - /'
}

usage() {
  echo "Usage: $0 setup <course-name>"
  list_courses
  exit 1
}

clone_or_update_repo() {
  download_courses_json

  local course=$1
  local repo_url=$2
  local course_dir="$BASE_DIR/$course"

  if [[ -z "$repo_url" ]]; then
    echo "Error: Unknown course '$course'"
    exit 1
  fi

  if [[ -d "$course_dir/.git" ]]; then
    echo "Updating $course repo..."
    git -C "$course_dir" pull
  else
    echo "Cloning $course repo..."
    mkdir -p "$BASE_DIR"
    git clone "$repo_url" "$course_dir"
  fi
}

run_setup_script() {
  local course=$1
  local course_dir="$BASE_DIR/$course"
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
  local repo_url=$(get_course_url "$course")

  if [[ -z "$repo_url" ]]; then
    echo "Unknown course: $course"
    usage
  fi

  clone_or_update_repo "$course" "$repo_url"
  run_setup_script "$course"
}

main "$@"
