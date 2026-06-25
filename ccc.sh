#!/usr/bin/env bash
set -euo pipefail

# Entry point for the CCC CLI
# calls into library helpers (courses, runtime, container_helpers, etc.).
# removed host mode and container mode in favor of a more centralized system

# Script directory — use the directory containing this script if it has lib/,
# otherwise fall back to the installed share directory.
# NOTE: might be able to be trimmed later depending on installation implementation
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
if [[ ! -d "$SCRIPT_DIR/lib" ]]; then
  if [[ -d "$HOME/.local/share/ccc" ]]; then
    SCRIPT_DIR="$HOME/.local/share/ccc"
  elif [[ -d "/usr/local/share/ccc" ]]; then
    SCRIPT_DIR="/usr/local/share/ccc"
  fi
fi

# Helper that loads files and gives more detailed errors
source_lib() {
  lib="$1"
  lib_file="$SCRIPT_DIR/lib/$lib.sh"

  if [ -f "$lib_file" ]; then
    # shellcheck disable=SC1090
    . "$lib_file"
  else
    printf 'ERROR: Library file not found: %s\n' "$lib_file" >&2
    exit 1
  fi
}

# Load core utilities and common helpers
source_lib "utils"
source_lib "config"
source_lib "registry"
source_lib "courses"
source_lib "container_helpers"
source_lib "runtime"
# Make REGISTRY_FILE available to libraries that expect it
REGISTRY_FILE="${registry_file:-$SCRIPT_DIR/registry.csv}"

# load config (courses directory and auto update preferences)
load_config 2>/dev/null || true

## Resolve and normalize CCC_COURSES_DIR early so all libraries see absolute pth
if [ -n "${CCC_COURSES_DIR:-}" ]; then
  case "$CCC_COURSES_DIR" in
    "~"|~/*) CCC_COURSES_DIR="${HOME}${CCC_COURSES_DIR#~}" ;;
  esac
  if cd "$CCC_COURSES_DIR" >/dev/null 2>&1; then
    CCC_COURSES_DIR=$(pwd -P)
  fi
fi

# Single dispatch for ccc commands
case "${1:-}" in
  auto-update)
    case "${2:-}" in
    status)
      printf 'CCC_AUTO_UPDATE=%s\n' "${CCC_AUTO_UPDATE:-false}"
      exit 0 ;;
    enable)
      set_config CCC_AUTO_UPDATE true
      printf '%s\n' "Automatic updates enabled"
      exit 0 ;;
    disable)
      set_config CCC_AUTO_UPDATE false
      printf '%s\n' "Automatic updates disabled"
      exit 0 ;;
    *)
      printf '%s\n' "Usage: ccc auto-update status|enable|disable" >&2
      exit 2 ;;
    esac ;;
  init)
    # Run interactive init (prompt_init handles reads)
    prompt_init
    exit 0 ;;
  list)
    # list available courses from registry
    registry_list
    exit 0 ;;
  open)
    # ccc open <course> [--local] [--no-shell]
    course="${2:-}"
    if [ -z "$course" ]; then
      printf '%s\n' "Usage: ccc open <course> [--local] [--no-shell]" >&2
      exit 2
    fi
    # shift past 'open' and the course name
    shift 2 || true
  # load open helper (required)
  source_lib "open"
  ccc_open "$course" "$@"
  exit $? ;;
  config)
    # ccc config get KEY | ccc config set KEY VALUE
    case "${2:-}" in
      get)
        key="${3:-}"
        if [ -z "$key" ]; then
          printf '%s\n' "Usage: ccc config get <KEY>" >&2
          exit 2
        fi
        if [ "$key" = "courses" ]; then
          key=CCC_COURSES_DIR
        fi
        load_config
        # shellcheck disable=SC2086
        eval "printf '%s\n' \"\${${key}:-}\""
        exit 0 ;;
      set)
        key="${3:-}"; value="${4:-}"
        if [ -z "$key" ] || [ -z "$value" ]; then
          printf '%s\n' "Usage: ccc config set <KEY> <VALUE>" >&2
          exit 2
        fi
        if [ "$key" = "courses" ]; then
          key=CCC_COURSES_DIR
        fi
        set_config "$key" "$value"
        printf 'Set %s\n' "$key"
        exit 0 ;;
      *)
        printf '%s\n' "Usage: ccc config get|set" >&2
        exit 2 ;;
    esac ;;
esac