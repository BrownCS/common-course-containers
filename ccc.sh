#!/usr/bin/env bash
set -euo pipefail

# Compatibility wrapper for the repository entrypoint.
# Delegates to the installed/dev `bin/ccc` script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/bin/ccc" "$@"
