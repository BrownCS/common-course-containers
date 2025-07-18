#!/usr/bin/env bash
set -e

VERSION="1.0.3"
BASE_DIR="/home/courses"

# Setup
COURSE_MAP="$BASE_DIR/courses.json"
REMOTE_COURSE_MAP="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/courses/courses.json"

# Self-update
SELF="$(realpath "$0")"
REMOTE_SELF="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/cscourse.sh"

# Logging
METADATA_DIR="$BASE_DIR/.cscourse"
LOG="$METADATA_DIR/metadata.csv"
ID_FILE="$METADATA_DIR/id.txt"

# Check that metadata is in place
init() {
  # BASE_DIR
  if [[ ! -d "$BASE_DIR" ]]; then
    echo "$BASE_DIR does not exist. Did you change the name?"
    exit 1
  fi
  if ! mountpoint -q "$BASE_DIR"; then
    echo "$BASE_DIR is not a mountpoint. Did you mount the directory?"
    exit 1
  fi

  # Course map
  if [[ ! -s "$COURSE_MAP" ]]; then
    echo '{}' >"$COURSE_MAP"
  fi

  # Metadata
  mkdir -p "$METADATA_DIR"

  if [[ ! -f "$LOG" ]]; then
    touch "$LOG"
    echo "ID,COURSE,COURSE_REPO,COMMIT,DIRPATH" >"$LOG"
  fi
  if [[ ! -f "$ID_FILE" ]]; then
    echo 1 >"$ID_FILE"
  fi
}

# Setup a course
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

  # Get and increment the ID
  local id=$(<"$ID_FILE")
  echo $((id + 1)) >"$ID_FILE"

  # Log the course
  log_course "$id" "$course" "$course_repo" "$dirpath"
  run_course_setup "$dirpath"
}

# Run the setup script for a course
run_course_setup() {
  local dirpath="$1"

  # Run the setup script
  local script="$dirpath/setup.sh"
  if [[ ! -f "$script" ]]; then
    echo "Error: No setup.sh found in $dirpath"
    exit 1
  fi

  echo "Running setup for $course..."
  chmod +x "$script"
  sandbox "$id" "$script"
}

# Log downloaded courses
log_course() {
  local id="$1"
  local course="$2"
  local course_repo="$3"
  local dirpath="$4"

  # Get the commit hash
  local commit="unknown"
  if [[ -d "$dirpath/.git" ]]; then
    commit=$(git -C "$dirpath" rev-parse HEAD 2>/dev/null)
  fi

  echo "$id,$course,$course_repo,$commit,$dirpath" >>"$LOG"
}

# Upgrade course
upgrade_course() {
  local id="$1"
  local line=$(tac "$LOG" | grep -m 1 "^$id,")
  if [[ -z "$line" ]]; then
    echo "Error: No course found with ID $id"
    return 1
  fi

  local dirpath=$(echo "$line" | cut -d',' -f5)
  if [[ ! -d "$dirpath" ]]; then
    echo "Error: $dirpath does not exist"
    return 1
  fi
  if [[ ! -d "$dirpath/.git" ]]; then
    echo "Error: $dirpath is not a git repo"
    return 1
  fi

  echo "Updating course in $dirpath..."
  git -C "$dirpath" pull

  # Run the bash script again
  run_course_setup "$dirpath"
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
      local new_version=$(grep -E '^VERSION=' "$TMPFILE" | cut -d= -f2 | tr -d '"')
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
list_courses() {
  if [[ ! -f "$LOG" ]]; then
    echo "No courses installed yet."
    exit 0
  fi

  column -s, -t <"$LOG"
}

# Usage
usage() {
  echo "Usage $0:"
  echo "Commands:"
  echo " setup <course>     Clone and run course setup"
  echo " upgrade <id>       Upgrade course to the latest version"
  echo " list               List downloaded courses"
  echo " update             Update self to the latest version"
  echo ""

  echo "Available courses:"
  jq -r 'keys_unsorted[]' "$COURSE_MAP" | sort | sed 's/^/  - /'
  exit 1
}

main() {
  init

  # cscourse update
  if [[ "$#" -eq 1 && "$1" == "update" ]]; then
    update_self
    update_course_map
    exit 0
  fi

  # cscourse list
  if [[ "$#" -eq 1 && "$1" == "list" || "$1" == "ls" ]]; then
    list_courses
    exit 0
  fi

  # cscourse setup <course>
  if [[ "$#" -eq 2 && "$1" == "setup" || "$1" == "s" ]]; then
    setup_course "$2"
    exit 0
  fi

  # cscourse upgrade <course>
  if [[ "$#" -eq 2 && "$1" == "upgrade" ]]; then
    upgrade_course "$2"
    exit 0
  fi

  if [[ "$#" -ge 1 ]]; then
    echo "Error: Invalid command: $*"
  fi

  usage
}

main "$@"
