#!/usr/bin/env bash
set -euo pipefail

# CCC Unified Script - Lightweight Environment Detection and Delegation

# Script directory - use installed location when available
if [[ -d "$HOME/.local/share/ccc" ]]; then
  SCRIPT_DIR="$HOME/.local/share/ccc"
elif [[ -d "/usr/local/share/ccc" ]]; then
  SCRIPT_DIR="/usr/local/share/ccc"
else
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
fi

# Load library functions
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

# Load core utilities for environment detection
source_lib "utils"

# Environment detection and delegation
if is_ccc_container; then
  # Container mode - load container functionality and run
  source_lib "courses"
  source_lib "container_mode"
  container_main "$@"
else
  # Host mode - load host functionality and run
  source_lib "courses"
  source_lib "container"
  source_lib "runtime"
  source_lib "host_mode"
  host_main "$@"
fi
