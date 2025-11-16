#!/bin/bash
set -euo pipefail
# Shared course and registry management functions

# Unified CSV parsing function
get_course_info() {
  local course="$1"
  local field="${2:-url}"  # url, base_image, name, semester, or all

  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo_error "Registry file not found: $REGISTRY_FILE"
    return 1
  fi

  # Parse CSV, skip comments and empty lines
  while IFS=',' read -r course_id repo_url name semester base_image; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue

    if [[ "$course_id" == "$course" ]]; then
      case "$field" in
        url) echo "$repo_url" ;;
        base_image) echo "${base_image:-default}" ;;
        name) echo "$name" ;;
        semester) echo "$semester" ;;
        all) echo "$course_id,$repo_url,$name,$semester,${base_image:-default}" ;;
        *) echo_error "Invalid field: $field"; return 1 ;;
      esac
      return 0
    fi
  done < "$REGISTRY_FILE"

  return 1
}

# Simplified registry functions using unified parser
get_course_url() {
  get_course_info "$1" "url"
}

get_course_base_image() {
  get_course_info "$1" "base_image"
}

list_available_courses() {
  if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo_error "Registry file not found: $REGISTRY_FILE"
    return 1
  fi

  echo "Available courses:"
  while IFS=',' read -r course_id repo_url name semester base_image; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue
    echo "  $course_id"
  done < "$REGISTRY_FILE"
}

find_course() {
  local course_url="$1"

  if [[ ! -f "$REGISTRY_FILE" ]]; then
    return 1
  fi

  # Parse CSV to find course by URL (can't use get_course_info since we're searching by URL)
  while IFS=',' read -r course_id repo_url name semester base_image; do
    # Skip comments and empty lines
    [[ "$course_id" =~ ^#.*$ || -z "$course_id" ]] && continue

    if [[ "$repo_url" == "$course_url" ]]; then
      echo "$course_id"
      return 0
    fi
  done < "$REGISTRY_FILE"

  return 1
}

# Course utility functions
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

# Course management functions
setup_course() {
  local course="$1"

  # Handle special case for default course
  if [[ "$course" == "default" ]]; then
    echo "Default container setup complete!"
    echo "You are now in the base CCC container environment."
    echo "To install a specific course, use: ccc setup <course-name>"
    return 0
  fi

  local course_url
  course_url="$(get_course_url "$course")"

  # Use exact course name as directory
  local courses_dir="$(get_base_dir)"
  local dirpath="$courses_dir/$course"
  local script="$dirpath/setup.sh"

  # Find the course_url
  # TODO: Error messages from setup_course are getting swallowed when run inside container
  # This should display error for invalid courses but may not be visible due to:
  # 1. Output buffering in container environment
  # 2. exit 1 terminating before output is flushed
  # 3. Potential issues with echo_error function in container context
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

  # Clone the repository (skip if already exists)
  if [[ ! -d "$dirpath" ]]; then
    echo_and_run git clone "$course_url" "$dirpath"
  else
    echo "Course directory already exists: $dirpath"
    echo "Updating repository..."
    echo_and_run cd "$dirpath" && git pull
  fi

  cd "$dirpath"

  # Run the setup script
  if [[ ! -f "$script" ]]; then
    echo_error "WARNING: No setup.sh found in $dirpath"
    echo "         Check with course staff if there should be a setup script for the course"
    echo "         Continuing without running setup script..."
    return 0
  fi

  echo_and_run chmod +x $script
  echo_and_run bash yes | $script

  # Add course context information to .envrc
  add_course_context "$course" "$dirpath"
}

list_courses() {
  local tmp=$(mktemp)
  echo "BASENAME,COURSE,COURSE_REPO,COMMIT" >"$tmp"

  local courses_dir="$(get_base_dir)"
  log_info "Checking courses in: $courses_dir"

  for dirpath in "$courses_dir"/*; do
    # Check that dirpath is a directory
    if [[ ! -d "$dirpath" ]]; then
      log_info "Skipping non-directory: $dirpath"
      continue
    fi

    log_info "Processing directory: $dirpath"

    # Get the course_url
    local course_url
    course_url="$(get_git_url "$dirpath")"
    if [[ "$?" -ne 0 ]]; then
      log_info "Failed to get git URL for: $dirpath"
      continue
    fi
    log_info "Found git URL: $course_url"

    # Find the course
    local course
    course="$(find_course "$course_url")"
    if [[ "$?" -ne 0 ]]; then
      log_info "Failed to find course for URL: $course_url"
      continue
    fi
    log_info "Found course: $course"

    # Get the commit
    local commit
    commit="$(get_git_commit "$dirpath")"
    if [[ "$?" -ne 0 ]]; then
      log_info "Failed to get git commit for: $dirpath"
      continue
    fi
    log_info "Found commit: $commit"

    local basename="$(basename "$dirpath")"
    log_info "Adding to list: $basename,$course,$course_url,$commit"

    echo "$basename,$course,$course_url,$commit" >>"$tmp"
  done

  column -s, -t <"$tmp"
}

upgrade_course() {
  local basename="$1"
  local courses_dir="$(get_base_dir)"
  local dirpath="$courses_dir/$basename"

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


handle_container_switching() {
  local target_course="$1"

  # Validate target course exists in registry
  if ! get_course_url "$target_course" >/dev/null 2>&1; then
    echo_error "ERROR: Course '$target_course' not found in registry"
    list_available_courses
    return 1
  fi

  echo_error "ERROR: Cannot switch containers from inside container"
  echo "You are currently inside a container. To switch to '$target_course':"
  echo ""
  echo "1. Exit this container:"
  echo "   exit"
  echo ""
  echo "2. Run the target course from the host:"
  echo "   ccc run $target_course"
  echo ""
  echo "This will start the appropriate container for '$target_course'."
}

add_course_context() {
  local course="$1"
  local dirpath="$2"
  local envrc_file="$dirpath/.envrc"

  # Check if .envrc already has course context
  if [[ -f "$envrc_file" ]] && grep -q "CCC_EXPECTED_COURSE" "$envrc_file"; then
    echo "Course context already exists in .envrc"
    return 0
  fi

  # Add course context to .envrc
  echo "Adding course context information to .envrc..."
  cat >> "$envrc_file" << EOF

# Course context information added by CCC
export CCC_EXPECTED_COURSE="$course"

# Optional: Show context info when entering directory
# Uncomment the next line to see course info when entering directory
# echo "Entered course directory: $course"
EOF

  echo "Course context added to $envrc_file"
}
