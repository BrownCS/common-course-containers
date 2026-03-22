#!/bin/bash
set -euo pipefail
# Shared utility functions

# Color definitions
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Printing utilities
echo_and_run() {
  echo -e "${BLUE}$*${RESET}"
  "$@"
}

echo_error() {
  local text="$1"
  echo -e "${RED}${text}${RESET}"
}

# Container detection
is_ccc_container() {
  [[ -f /etc/ccc-container ]]
}

# Logging functions with prefixes
log_info() {
  if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo -e "${BLUE}[INFO]${RESET} $1"
  fi
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${RESET} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${RESET} $1" >&2
}

# Configuration file management
get_config_dir() {
  echo "$HOME/.config/ccc"
}

get_config_file() {
  echo "$(get_config_dir)/config"
}

get_settings_file() {
  echo "$(get_config_dir)/settings"
}

save_courses_dir() {
  local courses_dir="$1"
  local config_dir="$(get_config_dir)"
  local config_file="$(get_config_file)"

  # Ensure config directory exists
  mkdir -p "$config_dir"

  # Convert to absolute path
  courses_dir="$(realpath "$courses_dir")"

  # Save to config file
  echo "COURSES_DIR=$courses_dir" >"$config_file"
}

load_courses_dir() {
  local config_file="$(get_config_file)"

  if [[ -f "$config_file" ]]; then
    # Source the config and return the courses directory
    source "$config_file"
    echo "$COURSES_DIR"
  fi
}

has_courses_config() {
  local config_file="$(get_config_file)"
  [[ -f "$config_file" ]] && grep -q "^COURSES_DIR=" "$config_file"
}

# Simple version management
get_version() {
  local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local version_file="$script_dir/VERSION"

  if [[ -f "$version_file" ]]; then
    cat "$version_file"
  else
    echo "unknown"
  fi
}

# Compare two semantic versions (returns 0 if v1 >= v2, 1 if v1 < v2)
version_compare() {
  local v1="$1"
  local v2="$2"

  # Remove 'v' prefix if present
  v1=$(echo "$v1" | sed 's/^v//')
  v2=$(echo "$v2" | sed 's/^v//')

  # Split versions into arrays
  IFS='.' read -ra V1 <<<"$v1"
  IFS='.' read -ra V2 <<<"$v2"

  # Compare major.minor.patch
  for i in {0..2}; do
    local n1=${V1[i]:-0}
    local n2=${V2[i]:-0}

    if [[ $n1 -gt $n2 ]]; then
      return 0 # v1 > v2
    elif [[ $n1 -lt $n2 ]]; then
      return 1 # v1 < v2
    fi
  done

  return 0 # v1 == v2
}

# Get latest version from GitHub releases
get_latest_version() {
  local repo_url="$CCC_UPDATE_API_URL"

  if command -v curl >/dev/null 2>&1; then
    curl -s "$repo_url" 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\?\([^"]*\)".*/\1/' 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$repo_url" 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\?\([^"]*\)".*/\1/' 2>/dev/null
  else
    echo ""
    return 1
  fi
}

# Self-update functionality using installer
update_self() {
  echo "Checking for CCC updates..."

  local current_version="$(get_version)"
  local latest_version="$(get_latest_version)"

  if [[ -z "$latest_version" ]]; then
    echo_error "Failed to check for updates (no internet connection?)"
    return 1
  fi

  echo "Current version: $current_version"
  echo "Latest version: $latest_version"

  if version_compare "$current_version" "$latest_version"; then
    echo "Already up to date"
    return 0
  fi

  echo "Newer version available: $latest_version"
  echo "Downloading and running installer..."

  # Download installer
  local installer_url="https://raw.githubusercontent.com/$CCC_UPDATE_REPO/v${latest_version}/install.sh"
  local tmp_installer=$(mktemp)

  if command -v curl >/dev/null 2>&1; then
    if ! curl -sSfL "$installer_url" -o "$tmp_installer"; then
      echo_error "Failed to download installer"
      rm -f "$tmp_installer"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q "$installer_url" -O "$tmp_installer"; then
      echo_error "Failed to download installer"
      rm -f "$tmp_installer"
      return 1
    fi
  else
    echo_error "Neither curl nor wget available"
    rm -f "$tmp_installer"
    return 1
  fi

  # Run installer
  chmod +x "$tmp_installer"
  echo "Running installer for version $latest_version..."
  "$tmp_installer"
  local install_result=$?

  # Cleanup
  rm -f "$tmp_installer"

  if [[ $install_result -eq 0 ]]; then
    echo "Successfully updated to version $latest_version"
  else
    echo_error "Installation failed"
    return 1
  fi
}

# Settings management
load_settings() {
  # Set defaults first
  CCC_IMAGE_PREFIX="${CCC_IMAGE_PREFIX:-ccc}"
  CCC_NETWORK_NAME="${CCC_NETWORK_NAME:-net-ccc}"
  CCC_DEFAULT_BASE_IMAGE="${CCC_DEFAULT_BASE_IMAGE:-ubuntu:noble}"
  CCC_MOUNT_PATH="${CCC_MOUNT_PATH:-/courses}"
  CCC_UPDATE_REPO="${CCC_UPDATE_REPO:-BrownCS/common-course-containers}"

  # Load user settings if they exist (only on host, not in container)
  local settings_file="$(get_settings_file)"
  if [[ -f "$settings_file" ]]; then
    source "$settings_file"
  fi

  # Derive dependent values
  CCC_UPDATE_API_URL="https://api.github.com/repos/$CCC_UPDATE_REPO/releases/latest"
}

create_default_settings() {
  local settings_file="$(get_settings_file)"
  local config_dir="$(get_config_dir)"

  # Ensure config directory exists
  mkdir -p "$config_dir"

  # Create default settings file if it doesn't exist
  if [[ ! -f "$settings_file" ]]; then
    cat > "$settings_file" << 'EOF'
# CCC Settings Configuration
# Customize these values to override defaults

# Container Configuration
CCC_IMAGE_PREFIX=ccc
CCC_NETWORK_NAME=net-ccc
CCC_DEFAULT_BASE_IMAGE=ubuntu:noble
CCC_MOUNT_PATH=/courses

# Update Repository
CCC_UPDATE_REPO=BrownCS/common-course-containers

# Uncomment and modify any settings you want to customize
# CCC_IMAGE_PREFIX=my-ccc
# CCC_NETWORK_NAME=my-net-ccc
# CCC_DEFAULT_BASE_IMAGE=ubuntu:jammy
EOF
    echo "Created default settings file: $settings_file"
  fi
}

# Cached update checking
get_cache_dir() {
  echo "$(get_config_dir)/cache"
}

get_last_update_check_file() {
  echo "$(get_cache_dir)/last_update_check"
}

get_pending_updates_file() {
  echo "$(get_cache_dir)/pending_updates"
}

# Check if we should check for updates (once per day)
should_check_updates() {
  local last_check_file="$(get_last_update_check_file)"
  local cache_dir="$(get_cache_dir)"

  # Ensure cache directory exists
  mkdir -p "$cache_dir"

  if [[ ! -f "$last_check_file" ]]; then
    return 0  # Never checked, should check
  fi

  local last_check=$(cat "$last_check_file" 2>/dev/null || echo "0")
  local current_time=$(date +%s)
  local day_in_seconds=86400

  # Check if more than 24 hours have passed
  if (( current_time - last_check > day_in_seconds )); then
    return 0  # Should check
  else
    return 1  # Too recent, skip check
  fi
}

# Update the last check timestamp
update_last_check_time() {
  local last_check_file="$(get_last_update_check_file)"
  local cache_dir="$(get_cache_dir)"
  mkdir -p "$cache_dir"
  date +%s > "$last_check_file"
}

# Check for CCC updates and cache result
check_ccc_updates_cached() {
  local current_version="$(get_version)"
  local latest_version="$(get_latest_version 2>/dev/null)"

  if [[ -z "$latest_version" ]]; then
    return 1  # Network error, don't cache anything
  fi

  local pending_file="$(get_pending_updates_file)"
  local cache_dir="$(get_cache_dir)"
  mkdir -p "$cache_dir"

  # Clear any existing CCC update from cache
  if [[ -f "$pending_file" ]]; then
    grep -v "^ccc:" "$pending_file" > "${pending_file}.tmp" 2>/dev/null || true
    mv "${pending_file}.tmp" "$pending_file" 2>/dev/null || true
  fi

  # Check if update is available
  if ! version_compare "$current_version" "$latest_version"; then
    echo "ccc:$current_version:$latest_version" >> "$pending_file"
    return 0  # Update available
  fi

  return 1  # No update
}

# Check for course updates and cache results
check_course_updates_cached() {
  local courses_dir
  if ! courses_dir="$(get_base_dir 2>/dev/null)"; then
    return 1  # No courses directory configured
  fi

  local pending_file="$(get_pending_updates_file)"
  local cache_dir="$(get_cache_dir)"
  mkdir -p "$cache_dir"

  # Clear any existing course updates from cache
  if [[ -f "$pending_file" ]]; then
    grep -v "^course:" "$pending_file" > "${pending_file}.tmp" 2>/dev/null || true
    mv "${pending_file}.tmp" "$pending_file" 2>/dev/null || true
  fi

  local has_updates=false

  for dirpath in "$courses_dir"/*; do
    if [[ ! -d "$dirpath/.git" ]]; then
      continue  # Not a git repository
    fi

    local course_name=$(basename "$dirpath")

    # Fetch updates silently in background
    if git -C "$dirpath" fetch --quiet 2>/dev/null; then
      # Check if there are commits ahead
      local ahead_count=$(git -C "$dirpath" rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
      if [[ "$ahead_count" -gt 0 ]]; then
        echo "course:$course_name:$ahead_count" >> "$pending_file"
        has_updates=true
      fi
    fi
  done

  if [[ "$has_updates" == "true" ]]; then
    return 0  # Updates available
  else
    return 1  # No updates
  fi
}

# Get cached pending updates
get_pending_updates() {
  local pending_file="$(get_pending_updates_file)"
  if [[ -f "$pending_file" ]] && [[ -s "$pending_file" ]]; then
    cat "$pending_file"
  fi
}

# Prompt for yes/no with default to No
prompt_yes_no() {
  local message="$1"
  local response

  echo -n "$message [y/N]: "
  read -r response

  case "$response" in
    [Yy]|[Yy][Ee][Ss])
      return 0  # Yes
      ;;
    *)
      return 1  # No (default)
      ;;
  esac
}

# Check for updates and prompt user if any are found
check_and_prompt_updates() {
  # Only check if enough time has passed
  if ! should_check_updates; then
    # Still show any cached pending updates
    local pending_updates="$(get_pending_updates)"
    if [[ -n "$pending_updates" ]]; then
      show_pending_updates "$pending_updates"
    fi
    return
  fi

  # Perform update checks
  local has_updates=false

  if check_ccc_updates_cached; then
    has_updates=true
  fi

  if check_course_updates_cached; then
    has_updates=true
  fi

  # Update timestamp
  update_last_check_time

  # Show any pending updates
  if [[ "$has_updates" == "true" ]]; then
    local pending_updates="$(get_pending_updates)"
    if [[ -n "$pending_updates" ]]; then
      show_pending_updates "$pending_updates"
    fi
  fi
}

# Show pending updates and prompt for action
show_pending_updates() {
  local pending_updates="$1"
  local ccc_update=""
  local course_updates=""

  echo ""
  echo -e "${YELLOW}Updates available:${RESET}"

  while IFS= read -r line; do
    if [[ "$line" =~ ^ccc:(.+):(.+)$ ]]; then
      ccc_update="$line"
      local current="${BASH_REMATCH[1]}"
      local latest="${BASH_REMATCH[2]}"
      echo "  • CCC tool: $current → $latest"
    elif [[ "$line" =~ ^course:(.+):(.+)$ ]]; then
      course_updates+="$line"$'\n'
      local course="${BASH_REMATCH[1]}"
      local count="${BASH_REMATCH[2]}"
      echo "  • Course $course: $count commit(s) behind"
    fi
  done <<< "$pending_updates"

  echo ""

  # Prompt for CCC update
  if [[ -n "$ccc_update" ]]; then
    if prompt_yes_no "Update CCC tool now?"; then
      update_self
      # Clear the CCC update from cache after successful update
      local pending_file="$(get_pending_updates_file)"
      if [[ -f "$pending_file" ]]; then
        grep -v "^ccc:" "$pending_file" > "${pending_file}.tmp" 2>/dev/null || true
        mv "${pending_file}.tmp" "$pending_file" 2>/dev/null || true
      fi
    fi
  fi

  # Prompt for course updates
  if [[ -n "$course_updates" ]]; then
    if prompt_yes_no "Update all courses now?"; then
      while IFS= read -r line; do
        if [[ "$line" =~ ^course:(.+):(.+)$ ]]; then
          local course="${BASH_REMATCH[1]}"
          echo "Updating course: $course"
          upgrade_course "$course"
        fi
      done <<< "$course_updates"

      # Clear course updates from cache after successful update
      local pending_file="$(get_pending_updates_file)"
      if [[ -f "$pending_file" ]]; then
        grep -v "^course:" "$pending_file" > "${pending_file}.tmp" 2>/dev/null || true
        mv "${pending_file}.tmp" "$pending_file" 2>/dev/null || true
      fi
    fi
  fi

  echo ""
}

# Auto-load settings when utils is sourced (host mode only)
if ! is_ccc_container; then
  load_settings
fi
