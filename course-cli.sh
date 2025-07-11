#!/usr/bin/env bash

set -e

# Configuration
BASE_DIR="/home/courses"
COURSES_FILE="$BASE_DIR/courses.json"
REMOTE="git@github.com:qiaochloe/unified-containers.git"

# Downlaod courses.json from the remote repository
# and save it in COURSES_FILE
download_courses_json() {
  BRANCH="courses"
  git archive --remote="$REMOTE" "$BRANCH" HEAD courses.json | tar -xO >"$COURSES_FILE"
}

# Given a course key, get the course URL from COURSES_FILE
get_course_url() {
  local course="$1"
  jq -r --arg course "$course" '.[$course] // empty' "$COURSES_FILE"
}

# List courses in COURSES_FILE
list_courses() {
  echo "Available courses:"
  jq -r 'keys_unsorted[]' "$COURSES_FILE" | sort | sed 's/^/  - /'
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

  clone_or_update_repo "$course"
  run_setup_script "$course"
}

main "$@"
