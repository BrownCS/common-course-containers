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

# Auto-load settings when utils is sourced (host mode only)
if ! is_ccc_container; then
  load_settings
fi
