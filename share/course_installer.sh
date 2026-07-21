#!/bin/sh
# Minimal POSIX installer for course manifests: packages.txt, links.txt, env.txt
# Usage: course_installer.sh <course_root>

set -eu

COURSE_ROOT=${1:-/opt/course}
REPO_ROOT="$COURSE_ROOT/dev-specs"
SETUP_DIR="$REPO_ROOT/setup"
PACKAGES_FILE="$SETUP_DIR/packages.txt"
LINKS_FILE="$SETUP_DIR/links.txt"
ENV_FILE="$SETUP_DIR/env.txt"
LOG_FILE="$SETUP_DIR/install.log"
ENV_DIR="$REPO_ROOT/env"
LINKS_MANIFEST="$SETUP_DIR/links.manifest"
DESIRED_LINKS_MANIFEST="$SETUP_DIR/links.manifest.new"
BIN_ROOT="$REPO_ROOT/bin"
LEGACY_BIN_ROOT="$COURSE_ROOT/bin"
LEGACY_AMD64_BIN_ROOT="$COURSE_ROOT/bin.amd64"
LEGACY_NATIVE_BIN_ROOT="$COURSE_ROOT/bin.native"
LEGACY_ENV_ROOT="$COURSE_ROOT/env"

mkdir -p "$SETUP_DIR"
: > "$LOG_FILE"
: > "$DESIRED_LINKS_MANIFEST"

rm -rf "$LEGACY_BIN_ROOT" "$LEGACY_AMD64_BIN_ROOT" "$LEGACY_NATIVE_BIN_ROOT" "$LEGACY_ENV_ROOT"

cleanup_temp_links_manifest() {
  rm -f "$DESIRED_LINKS_MANIFEST" "$LINKS_MANIFEST.tmp" "$LINKS_MANIFEST.new"
}

trap cleanup_temp_links_manifest EXIT HUP INT TERM

log() {
  printf "%s\n" "$1" >> "$LOG_FILE"
}

package_is_installed() {
  pkg="$1"
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'
}

# Phase A: install packages
log "Starting package install"
PACKAGES=""
MISSING_PACKAGES=""
HAS_AMD64=0
if [ -f "$PACKAGES_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    PACKAGES="$PACKAGES $line"
    if package_is_installed "$line"; then
      log "Package already installed: $line"
    else
      MISSING_PACKAGES="$MISSING_PACKAGES $line"
      case "$line" in
        *:amd64) HAS_AMD64=1 ;;
      esac
    fi
  done < "$PACKAGES_FILE"
else
  log "No packages file found at $PACKAGES_FILE"
fi

if [ -n "$(printf '%s' "$MISSING_PACKAGES" | sed 's/[[:space:]]//g')" ]; then
  # Convert missing packages into positional args safely.
  set -- $MISSING_PACKAGES

  if [ "$HAS_AMD64" -eq 1 ]; then
    log "Detected amd64 packages; enabling amd64 multiarch"
    dpkg --add-architecture amd64 2>>"$LOG_FILE" || true
    apt-get update >>"$LOG_FILE" 2>&1 || true
  fi

  log "Installing missing packages: $*"
  apt-get update >>"$LOG_FILE" 2>&1 || true
  apt-get install -y --no-install-recommends "$@" >>"$LOG_FILE" 2>&1 || {
    log "apt-get install failed"
    exit 1
  }
  log "Package installation complete"
else
  log "All requested packages already installed"
fi

# Phase B: discover binaries and create symlinks
log "Discovering binaries and creating symlinks"

# Ensure course bin root
COURSE_BIN="$BIN_ROOT"
mkdir -p "$COURSE_BIN"

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
}

record_link() {
  printf '%s\n' "$1" >> "$DESIRED_LINKS_MANIFEST"
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
    target_path="$REPO_ROOT/bin.$arch_prefix/bin/$target"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$src_path" ]; then
      create_symlink "$src_path" "$target_path"
      record_link "$target_path"
      # Also create top-level canonical link
      create_symlink "$target_path" "$COURSE_BIN/$target"
      record_link "$COURSE_BIN/$target"
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
  arch_dir="$REPO_ROOT/bin.amd64/bin"
  mkdir -p "$arch_dir"
  create_symlink "$f" "$arch_dir/$canonical_nover"
  record_link "$arch_dir/$canonical_nover"
  create_symlink "$arch_dir/$canonical_nover" "$COURSE_BIN/$canonical_nover"
  record_link "$COURSE_BIN/$canonical_nover"
done

# Also handle binaries that end with -13 in /usr/bin (e.g. g++-13)
for f in /usr/bin/*-13; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  canonical_nover="$(printf '%s' "$base" | sed 's/-13$//')"
  arch_dir="$REPO_ROOT/bin.native/bin"
  mkdir -p "$arch_dir"
  create_symlink "$f" "$arch_dir/$canonical_nover"
  record_link "$arch_dir/$canonical_nover"
  create_symlink "$arch_dir/$canonical_nover" "$COURSE_BIN/$canonical_nover"
  record_link "$COURSE_BIN/$canonical_nover"
done

if [ -f "$LINKS_MANIFEST" ]; then
  while IFS= read -r old_link || [ -n "$old_link" ]; do
    [ -n "$old_link" ] || continue
    if ! grep -qxF "$old_link" "$DESIRED_LINKS_MANIFEST" 2>/dev/null; then
      rm -f "$old_link" 2>/dev/null || true
    fi
  done < "$LINKS_MANIFEST"
fi

sort -u "$DESIRED_LINKS_MANIFEST" > "$LINKS_MANIFEST.tmp"
mv "$LINKS_MANIFEST.tmp" "$LINKS_MANIFEST"
rm -f "$DESIRED_LINKS_MANIFEST"

log "Symlink creation complete"

# Phase C: apply environment variables
log "Applying environment variables"
mkdir -p "$ENV_DIR"
: > "$ENV_DIR/course.env"
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    # validate KEY=VALUE
    case "$line" in
      *=*) key="${line%%=*}" ; val="${line#*=}" ;;
      *) log "malformed env line: $line" ; continue ;;
    esac
    printf 'export %s="%s"\n' "$key" "$val" >> "$ENV_DIR/course.env"
  done < "$ENV_FILE"
else
  log "No env file at $ENV_FILE"
fi

printf 'export PATH="%s/bin:$PATH"\n' "$REPO_ROOT" >> "$ENV_DIR/course.env"

log "Environment applied; file at $ENV_DIR/course.env"

log "Installer finished successfully"
exit 0
