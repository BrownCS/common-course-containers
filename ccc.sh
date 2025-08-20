#!/usr/bin/env bash

VERSION="1.0.5"
BASE_DIR="/home/courses"

# Self-update
SELF="$(realpath "$0")"
REMOTE_SELF="https://raw.githubusercontent.com/qiaochloe/unified-containers/main/ccc.sh"

declare -A COURSE_URLS
COURSE_URLS=(
  ["300-demo"]="https://github.com/qiaochloe/300-demo.git"
  [example]="https://github.com/qiaochloe/example-course-repo.git"
)

init() {
  # Base directory
  if [[ ! -d "$BASE_DIR" ]]; then
    echo "$BASE_DIR does not exist. Did you change the name?"
    exit 1
  fi

  # TODO: need to check that this works on desktop
  if ! mountpoint -q "$BASE_DIR"; then
    echo "$BASE_DIR is not a mountpoint. Did you mount the directory?"
    exit 1
  fi

  # TODO: update_self
  # update_self
}

setup_course() {
  local course="$1"
  local course_url="${COURSE_URLS["$course"]}"

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
  if [[ -z "$course_url" ]]; then
    echo_error "ERROR: Could not find remote course repository for '$course'"
    echo "(1) To install a course repository manually, run: "
    echo "       git clone <course-url>"
    echo "       chmod +x $script"
    echo "       bash $script"
    echo "(2) To add a new course to ccc, email problem@cs.brown.edu"
    echo "    with the <course> and the <course-url>"
    echo "(3) To modify the course index locally during development,"
    echo "    edit the COURSE_URLS array in /usr/local/bin/ccc"
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
  echo_and_run bash $script
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
  for course in "${!COURSE_URLS[@]}"; do
    if [[ "${COURSE_URLS["$course"]}" == "$course_url" ]]; then
      echo "$course"
      return 0
    fi
  done
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

# Usage
usage() {
  echo "Usage $0:"
  echo "Commands:"
  echo "  setup <course>      Clone and run course setup"
  echo "  list                List downloaded courses"
  echo "  upgrade <basename>  Upgrade course to the latest version"
  echo "  update              Update ccc to the latest version"
  echo ""

  echo "Available courses:"
  for course in "${!COURSE_URLS[@]}"; do
    echo "  $course"
  done

  echo "Example: $0 setup 300"
  exit 0
}

main() {
  init

  # ccc list
  if [[ "$#" -eq 1 && ("$1" == "list" || "$1" == "ls") ]]; then
    list_courses
    exit 0
  fi

  # ccc setup <course>
  if [[ "$#" -eq 2 && "$1" == "setup" || "$1" == "s" ]]; then
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
