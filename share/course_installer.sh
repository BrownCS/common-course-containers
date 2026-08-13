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
AMD64_BIN_ROOT="$REPO_ROOT/bin.amd64"
NATIVE_BIN_ROOT="$REPO_ROOT/bin.native"

mkdir -p "$SETUP_DIR"
: > "$LOG_FILE"
: > "$DESIRED_LINKS_MANIFEST"

cleanup_temp_links_manifest() {
  rm -f "$DESIRED_LINKS_MANIFEST" "$LINKS_MANIFEST.tmp" "$LINKS_MANIFEST.new"
}

trap cleanup_temp_links_manifest EXIT HUP INT TERM

log() {
  printf "%s\n" "$1" >> "$LOG_FILE"
}

trim_line() {
  printf '%s' "$1" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

package_is_installed() {
  pkg="$1"
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'
}

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo env PATH="$PATH" "$@"
  fi
}

apt_run() {
  # Let apt wait briefly if the dpkg lock is transiently held.
  run_root apt-get -o Dpkg::Use-Pty=0 -o DPkg::Lock::Timeout=60 "$@"
}

# added august 6th, 2026 -- ccc open was breaking and this resolved it
# appeared to be a package installation issue, not sure how it happened.
repair_package_manager() {
  log "Repairing package manager state if needed"
  run_root dpkg --configure -a >>"$LOG_FILE" 2>&1 || true
  run_root apt --fix-broken install -y >>"$LOG_FILE" 2>&1 || true
}

link_file_into_course_bin() {
  src="$1"
  target="$2"
  target_path="$COURSE_BIN/$target"
  create_symlink "$src" "$target_path"
  record_link "$target_path"
}

link_package_binaries() {
  pkg="$1"
  arch_root="$2"

  dpkg-query -L "$pkg" 2>/dev/null | while IFS= read -r path || [ -n "$path" ]; do
    case "$path" in
      /usr/bin/*|/usr/local/bin/*|/bin/*)
        if [ -f "$path" ] && [ -x "$path" ]; then
          link_file_into_course_bin "$path" "$(basename "$path")"
          if [ -n "$arch_root" ]; then
            arch_target="$arch_root/$(basename "$path")"
            create_symlink "$path" "$arch_target"
            record_link "$arch_target"
          fi
        fi
        ;;
    esac
  done
}

# Phase A: install packages
log "Starting package install"
PACKAGES=""
MISSING_PACKAGES=""
HAS_AMD64=0
if [ -f "$PACKAGES_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim_line "$line")"
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

if [ -n "$MISSING_PACKAGES" ]; then
  # Convert missing packages into positional args safely.
  set -- $MISSING_PACKAGES

  repair_package_manager

  if [ "$HAS_AMD64" -eq 1 ]; then
    log "Detected amd64 packages; enabling amd64 multiarch"
    run_root dpkg --add-architecture amd64 2>>"$LOG_FILE" || true
  fi

  log "Refreshing package indexes"
  apt_run update >>"$LOG_FILE" 2>&1 || true

  log "Installing missing packages: $*"
  apt_run install -y --no-install-recommends "$@" >>"$LOG_FILE" 2>&1 || {
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
mkdir -p "$AMD64_BIN_ROOT" "$NATIVE_BIN_ROOT"

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

if [ -n "$PACKAGES" ]; then
  for pkg in $PACKAGES; do
    case "$pkg" in
      *:amd64)
        link_package_binaries "$pkg" "$AMD64_BIN_ROOT"
        ;;
      *)
        link_package_binaries "$pkg" "$NATIVE_BIN_ROOT"
        ;;
    esac
  done
fi

# Honor explicit links.txt if present
if [ -f "$LINKS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim_line "$line")"
    [ -z "$line" ] && continue
    # Expect format: <source> -> <target>
    case "$line" in
      *'->'*) src="$(trim_line "${line%%->*}")" ; target="$(trim_line "${line#*->}")" ;;
      *) continue ;;
    esac
    if printf '%s' "$src" | grep -q ':'; then
      src_path="${src#*:}"
    else
      src_path="$src"
    fi
    target_path="$COURSE_BIN/$target"
    if [ -f "$src_path" ]; then
      create_symlink "$src_path" "$target_path"
      record_link "$target_path"
    else
      log "explicit source not found: $src_path"
    fi
  done < "$LINKS_FILE"
fi

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
