#!/usr/bin/env bash

set -e

BASE_DIR="/home/courses"

# For setup
COURSE_MAP="$BASE_DIR/courses.json"
REMOTE_COURSE_MAP="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/courses/courses.json"

# For self-update
SELF="$(realpath "$0")"
REMOTE_SELF="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/cscourse.sh"

# Given a course key, get the course URL from COURSE_MAP
get_course_url() {
  local course="$1"
  jq -r --arg course "$course" '.[$course] // empty' "$COURSE_MAP"
}

# Given a course name and a course repo url, download the repo
clone_or_update_repo() {
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

# Given a course name, run the setup script
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

# Download update courses.json from the remote repo
update_course_map() {
  curl -sSfL "$REMOTE_COURSE_MAP" -o "$COURSE_MAP"
}

# Update cscourse.sh with the latest version from remote repository
update_self() {
  echo "Checking for latest version of cscourse..."
  TMPFILE=$(mktemp)
  if curl -sSfL "$REMOTE_SELF" -o "$TMPFILE"; then
    if ! cmp -s "$SELF" "$TMPFILE"; then
      chmod +x "$TMPFILE"
      cp "$TMPFILE" "$SELF"
      echo "Updated to latest version"
    else
      echo "Already up to date"
    fi
  else
    echo "Failed to check for update"
  fi
  rm -f "$TMPFILE"
}

# Usage
usage() {
  echo "Usage $0:"
  echo "Commands:"
  echo " setup <course>   Clone and run course setup"
  echo " update           Update cscourse to the latest version"
  echo ""

  update_course_map
  echo "Available courses:"
  jq -r 'keys_unsorted[]' "$COURSE_MAP" | sort | sed 's/^/  - /'
  exit 1
}

main() {
  # cscourse update
  if [[ "$#" -eq 1 && "$1" == "update" ]]; then
    update_self
    exit 0
  fi

  # cscourse setup <course>
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
