#!/usr/bin/env bash
set -euo pipefail

# Entry point for the CCC CLI
# Detects whether we're on the host or in the container
# and dispatches to either lib/host_mode.sh or lib/container_mode.sh

# Script directory — use the directory containing this script if it has lib/,
# otherwise fall back to the installed share directory.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
if [[ ! -d "$SCRIPT_DIR/lib" ]]; then
  if [[ -d "$HOME/.local/share/ccc" ]]; then
    SCRIPT_DIR="$HOME/.local/share/ccc"
  elif [[ -d "/usr/local/share/ccc" ]]; then
    SCRIPT_DIR="/usr/local/share/ccc"
  fi
fi

# Load library
source_lib() {
  local lib="$1"
  local lib_file="$SCRIPT_DIR/lib/$lib.sh"

  if [[ -f "$lib_file" ]]; then
    source "$lib_file"
  else
    echo "ERROR: Library file not found: $lib_file" >&2
    exit 1
  fi
}

# Load core utilities
source_lib "utils"

# Load new config and registry helpers (safe to be POSIX sh compatible)
if [ -f "$SCRIPT_DIR/lib/config.sh" ]; then
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/lib/config.sh"
fi
if [ -f "$SCRIPT_DIR/lib/registry.sh" ]; then
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/lib/registry.sh"
fi

# Make sure config is loaded early
load_config 2>/dev/null || true

# Dispatch
if [ "$#" -ge 1 ] && [ "$1" = "auto-update" ]; then
  # ccc auto-update status|enable|disable
  case "${2:-}" in
  status)
    load_config
    echo "CCC_AUTO_UPDATE=${CCC_AUTO_UPDATE:-false}"
    exit 0
    ;;
  enable)
    set_config CCC_AUTO_UPDATE true
    echo "Automatic updates enabled"
    exit 0
    ;;
  disable)
    set_config CCC_AUTO_UPDATE false
    echo "Automatic updates disabled"
    exit 0
    ;;
  *)
    echo "Usage: ccc auto-update status|enable|disable"
    exit 2
    ;;
  esac
fi

# Top-level admin commands: init, list, config
case "${1:-}" in
  init)
    # Run interactive init (prompt_init handles reads)
    prompt_init
    exit 0
    ;;
  list)
    # list available courses from registry
    registry_list
    exit 0
    ;;
  open)
    # ccc open <course> [--no-shell]
    course="${2:-}"
    if [ -z "$course" ]; then
      echo "Usage: ccc open <course> [--no-shell]" >&2
      exit 2
    fi
    # shift past 'open' and the course name
    shift 2 || true
    # load open helper
    if [ -f "$SCRIPT_DIR/lib/open.sh" ]; then
      # shellcheck disable=SC1090
      . "$SCRIPT_DIR/lib/open.sh"
      open_host "$course" "$@"
      exit $?
    else
      echo "Open functionality not available" >&2
      exit 2
    fi
    ;;
  config)
    # ccc config get KEY | ccc config set KEY VALUE
    case "${2:-}" in
      get)
        key="${3:-}"
        if [ -z "$key" ]; then
          echo "Usage: ccc config get <KEY>" >&2
          exit 2
        fi
        load_config
        # shellcheck disable=SC2086
        eval "printf '%s\n' \"\${${key}:-}\""
        exit 0
        ;;
      set)
        key="${3:-}"; value="${4:-}"
        if [ -z "$key" ] || [ -z "$value" ]; then
          echo "Usage: ccc config set <KEY> <VALUE>" >&2
          exit 2
        fi
        set_config "$key" "$value"
        echo "Set $key"
        exit 0
        ;;
      *)
        echo "Usage: ccc config get|set" >&2
        exit 2
        ;;
    esac
    ;;
esac

# if is_ccc_container; then
#   source_lib "courses"
#   source_lib "container_mode"
#   container_main "$@"
# else
#   source_lib "courses"
#   source_lib "container"
#   source_lib "runtime"
#   source_lib "host_mode"
#   host_main "$@"
# fi
