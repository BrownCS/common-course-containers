#!/usr/bin/env bash
set -e

VERSION="1.0.0"

BASE_DIR="/home/courses"

# Setup
COURSE_MAP="$BASE_DIR/courses.json"
REMOTE_COURSE_MAP="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/courses/courses.json"

# Self-update
SELF="$(realpath "$0")"
REMOTE_SELF="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/cscourse.sh"

# Logging
LOG="$BASE_DIR/metadata.log"

get_version() {
  grep -E '^VERSION=' "$1" | cut -d= -f2 | tr -d '"'
}

# Log downloaded courses
log_course() {
  local course="$1"
  local course_repo="$2"
  local dirpath="$3"
  local commit_hash

  # Get the commit hash
  if [[ -d "$course_dir/.git" ]]; then
    commit_hash=$(git -C "$dirpath" rev-parse HEAD 2>/dev/null)
  else
    commit_hash="unknown"
  fi

  {
    echo "course: $course"
    echo "course_repo: $course_repo"
    echo "commit_hash: $commit_hash"
    echo "dirpath: $dirpath"
    echo "---"
  } >>"$LOG"
}

# Clone and run the setup script for a course
setup_course() {
  local course="$1"

  # Get the remote course repository URL from courses.json
  local course_repo=$(jq -r --arg course "$course" '.[$course] // empty' "$COURSE_MAP")
  if [[ -z "$course_repo" ]]; then
    echo "Could not find remote course repository for '$course' in courses.json"
    exit 1
  fi

  # Get a dirpath that doesn't exist yet
  local dirname="$course"
  local base="$BASE_DIR/$course"
  local dirpath="$base"
  local i=1
  while [[ -e "$dirpath" ]]; do
    dirpath="${base}-$i"
    ((i++))
  done

  # Clone the repository
  echo "Cloning $course repo to $dirpath"
  mkdir -p "$BASE_DIR"
  git clone "$course_repo" "$dirpath"

  # Log the course
  log_course "$course" "$course_repo" "$dirpath"

  # Run the setup script
  local script="$dirpath/setup.sh"
  if [[ ! -f "$script" ]]; then
    echo "Error: No setup.sh found in $dirpath"
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
      local new_version=$(get_version "$TMPFILE")
      echo "Updated to latest version $new_version"
    else
      echo "Already up to date"
    fi
  else
    echo "Failed to check for update"
  fi
  rm -f "$TMPFILE"
}

# List downloaded courses
list() {
  cat "$LOG"
}

# Usage
usage() {
  echo "Usage $0:"
  echo "Commands:"
  echo " setup <course>   Clone and run course setup"
  echo " update           Update cscourse to the latest version"
  echo " list             List downloaded courses"
  echo ""

  echo "Available courses:"
  jq -r 'keys_unsorted[]' "$COURSE_MAP" | sort | sed 's/^/  - /'
  exit 1
}

main() {
  # cscourse update
  if [[ "$#" -eq 1 && "$1" == "update" ]]; then
    update_course_map
    update_self
    exit 0
  fi

  # cscourse list
  if [[ "$#" -eq 1 && "$1" == "list" ]]; then
    list
    exit 0
  fi

  # cscourse setup <course> [-o <dirname>]
  if [[ "$#" -eq 2 && "$1" == "setup" ]]; then
    setup_course "$2"
    exit 0
  fi

  if [[ "$#" -ge 1 ]]; then
    echo "Error: Invalid command: $*"
  fi

  usage
}

main "$@"
