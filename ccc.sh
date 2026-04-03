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

# Dispatch
if is_ccc_container; then
  source_lib "courses"
  source_lib "container_mode"
  container_main "$@"
else
  source_lib "courses"
  source_lib "container"
  source_lib "runtime"
  source_lib "host_mode"
  host_main "$@"
fi
