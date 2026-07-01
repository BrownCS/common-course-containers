#!/bin/sh
# Minimal POSIX installer for course manifests: packages.txt, links.txt, env.txt
# Usage: course_installer.sh <course_root>

set -eu

COURSE_ROOT=${1:-/opt/course}
SETUP_DIR="$COURSE_ROOT/setup"
INSTALLER_CACHE_FILE="$COURSE_ROOT/.ccc-installer-ran"
PACKAGES_FILE="$SETUP_DIR/packages.txt"
LINKS_FILE="$SETUP_DIR/links.txt"
ENV_FILE="$SETUP_DIR/env.txt"
LOG_FILE="$SETUP_DIR/install.log"
APPLIED_PACKAGES="$SETUP_DIR/applied-packages.txt"
LINKS_MANIFEST="$SETUP_DIR/links.manifest"
APPLIED_ENV="$SETUP_DIR/applied-env.txt"

mkdir -p "$SETUP_DIR"
if [ -f "$INSTALLER_CACHE_FILE" ]; then
  exit 0
fi
: > "$LOG_FILE"

if [ ! -f "$PACKAGES_FILE" ] && [ ! -f "$LINKS_FILE" ] && [ ! -f "$ENV_FILE" ]; then
  : > "$INSTALLER_CACHE_FILE"
  exit 0
fi

log() {
  printf "%s\n" "$1" >> "$LOG_FILE"
}

# Phase A: install packages
log "Starting package install"
PACKAGES=""
HAS_AMD64=0
if [ -f "$PACKAGES_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    PACKAGES="$PACKAGES $line"
    case "$line" in
      *:amd64) HAS_AMD64=1 ;;
    esac
  done < "$PACKAGES_FILE"
else
  log "No packages file found at $PACKAGES_FILE"
fi

# Add multiarch if needed
if [ "$HAS_AMD64" -eq 1 ]; then
  log "Detected amd64 packages; enabling amd64 multiarch"
  dpkg --add-architecture amd64 2>>"$LOG_FILE" || true
  apt-get update >>"$LOG_FILE" 2>&1 || true
fi

# Install packages (idempotent via apt)
if [ -n "$(printf '%s' "$PACKAGES" | sed 's/[[:space:]]//g')" ]; then
  # Convert PACKAGES into positional args safely
  set -- $PACKAGES
  log "Installing packages: $*"
  apt-get update >>"$LOG_FILE" 2>&1 || true
  apt-get install -y --no-install-recommends "$@" >>"$LOG_FILE" 2>&1 || {
    log "apt-get install failed"
    exit 1
  }
  printf "%s\n" "$@" > "$APPLIED_PACKAGES"
  log "Package installation complete"
else
  log "No packages to install"
fi

# Phase B: discover binaries and create symlinks
log "Discovering binaries and creating symlinks"

# Ensure course bin root
COURSE_BIN="$COURSE_ROOT/bin"
mkdir -p "$COURSE_BIN"

# Clear previous manifest
: > "$LINKS_MANIFEST"

# Helper to create symlink and record
create_symlink() {
  src="$1"; dst="$2"
  dst_dir=$(dirname "$dst")
  mkdir -p "$dst_dir"
  # If destination exists and points correctly, skip
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  ln -sf "$src" "$dst"
  printf "%s -> %s\n" "$dst" "$src" >> "$LINKS_MANIFEST"
}

# Honor explicit links.txt if present
if [ -f "$LINKS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    # Expect format: <source> -> <target>
    case "$line" in
      *'->'*) src="$(printf '%s' "$line" | awk -F'->' '{print $1}' | sed 's/[[:space:]]*$//')" ; target="$(printf '%s' "$line" | awk -F'->' '{print $2}' | sed 's/^[[:space:]]*//')" ;;
      *) continue ;;
    esac
    # Handle arch-prefixed source like x86_64:/usr/bin/...
    if printf '%s' "$src" | grep -q ':'; then
      arch_prefix="$(printf '%s' "$src" | awk -F: '{print $1}')"
      src_path="$(printf '%s' "$src" | awk -F: '{print $2}')"
    else
      arch_prefix="amd64"
      src_path="$src"
    fi
    target_path="$COURSE_ROOT/bin.$arch_prefix/bin/$target"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$src_path" ]; then
      create_symlink "$src_path" "$target_path"
      # Also create top-level canonical link
      create_symlink "$target_path" "$COURSE_BIN/$target"
    else
      log "explicit source not found: $src_path"
    fi
  done < "$LINKS_FILE"
fi

# Heuristic discovery: multiarch-prefixed binaries in /usr/bin
for f in /usr/bin/*x86_64-linux-gnu-*; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  canonical="${base#x86_64-linux-gnu-}"
  # strip trailing -13 if present
  canonical_nover="$(printf '%s' "$canonical" | sed 's/-13$//')"
  arch_dir="$COURSE_ROOT/bin.amd64/bin"
  mkdir -p "$arch_dir"
  create_symlink "$f" "$arch_dir/$canonical_nover"
  create_symlink "$arch_dir/$canonical_nover" "$COURSE_BIN/$canonical_nover"
done

# Also handle binaries that end with -13 in /usr/bin (e.g. g++-13)
for f in /usr/bin/*-13; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  canonical_nover="$(printf '%s' "$base" | sed 's/-13$//')"
  arch_dir="$COURSE_ROOT/bin.native/bin"
  mkdir -p "$arch_dir"
  create_symlink "$f" "$arch_dir/$canonical_nover"
  create_symlink "$arch_dir/$canonical_nover" "$COURSE_BIN/$canonical_nover"
done

log "Symlink creation complete; manifest at $LINKS_MANIFEST"

# Phase C: apply environment variables
log "Applying environment variables"
mkdir -p "$COURSE_ROOT/env"
: > "$APPLIED_ENV"
: > "$COURSE_ROOT/env/course.env"
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    # validate KEY=VALUE
    case "$line" in
      *=*) key="${line%%=*}" ; val="${line#*=}" ;;
      *) log "malformed env line: $line" ; continue ;;
    esac
    printf '%s=%s\n' "$key" "$val" >> "$APPLIED_ENV"
    printf 'export %s="%s"\n' "$key" "$val" >> "$COURSE_ROOT/env/course.env"
  done < "$ENV_FILE"
else
  log "No env file at $ENV_FILE"
fi

log "Environment applied; file at $COURSE_ROOT/env/course.env"

log "Installer finished successfully"
: > "$INSTALLER_CACHE_FILE"
exit 0
