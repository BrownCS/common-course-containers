#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage $0 <course_id> [setup.sh]"
}

# Use the course id to identify the course
COURSE_ID="${1:-}"
if [[ -z "$COURSE_ID" ]]; then
  usage
  exit 1
fi
shift

# Directory to store logs
COURSE_DIR="/home/courses"
LOG_FILE="$COURSE_DIR/.cscourse/$COURSE_ID/apt.txt"

if [[ ! -d "$COURSE_DIR" ]]; then
  echo "$COURSE_DIR does not exist. Did you change the name?"
  exit 1
fi
if ! mountpoint -q "$COURSE_DIR"; then
  echo "$COURSE_DIR is not a mountpoint. Did you mount the directory?"
  exit 1
fi
mkdir -p "$(dirname "$LOG_FILE")"

# Directory to store shims
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="$SCRIPT_DIR/.sandbox"
BIN_DIR="$SANDBOX_DIR/bin"

mkdir -p "$SANDBOX_DIR"
mkdir -p "$BIN_DIR"

# apt-get shim
cat >"$BIN_DIR/apt-get" <<'EOF'
#!/bin/bash
echo "I am here!"
LOG_FILE="${CSC_INTERCEPT_LOG:-.cscourse/default.txt}"
if [[ "$1" == "install" ]]; then
  for arg in "${@:2}"; do
    if [[ "$arg" != -* ]]; then
      echo "$arg" >> "$LOG_FILE"
    fi
  done
fi
exec /usr/bin/apt-get "$@"
EOF
chmod +x "$BIN_DIR/apt-get"

# Run the setup script in the sandboxed environment
export CSC_INTERCEPT_LOG="$LOG_FILE"
export PATH="$BIN_DIR:$PATH"
bash "$@"

echo "Sandbox run complete."
echo "Packages listed (apt):"
sort -u "$LOG_FILE"

