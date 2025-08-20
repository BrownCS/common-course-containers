#!/bin/bash
set -euo pipefail

# Wrapper for apt and apt-get that intercepts installs.
# If the package is already installed, it will skip it.
# Otherwise, it will try to switch into root.

# Check that the path ends in apt or apt-get
command="$(basename "$0")"
case "$command" in
apt) REAL_COMMAND=/usr/bin/apt ;;
apt-get) REAL_COMMAND=/usr/bin/apt-get ;;
*)
  echo "[apt-sandbox] invoke as apt or apt-get"
  exit 2
  ;;
esac

args=("$@")

# Always run update with sudo
if [[ " ${args[*]} " =~ " update " ]]; then
  echo "[apt-sandbox] running update with sudo"
  exec sudo "$REAL_COMMAND" "$@"
fi

# Find the first occurence of "install"
install_idx=-1
for i in "${!args[@]}"; do
  if [[ "${args[i]}" == "install" ]]; then
    install_idx="$i"
    break
  fi
done

# If there is no install command, pass through
if ((install_idx < 0)); then
  exec "$REAL_COMMAND" "$@"
fi

# Parse <pre-opts> install <cmd-opts> <pkgs>
pre_opts=("${args[@]:0:install_idx}")
cmd_opts=()
pkgs=()

rest=("${args[@]:install_idx+1}")
stop_opts=0
for arg in "${rest[@]}"; do
  if ((!stop_opts)) && [[ $arg == -- ]]; then
    stop_opts=1
    continue
  fi
  if ((!stop_opts)) && [[ $arg == -* ]]; then
    cmd_opts+=("$arg")
  else
    pkgs+=("$arg")
  fi
done

# Get the list of packages to install
pkg_is_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}' ${pkg} 2>/dev/null | grep -q '^install ok installed$'
}

not_installed=()
for pkg in "${pkgs[@]}"; do
  if ! pkg_is_installed "$pkg"; then
    not_installed+=("$pkg")
  fi
done

if ((${#not_installed[@]} == 0)); then
  echo "[apt-sandbox] All packages already installed, skipping"
  exit 0
fi

# Install
echo "[apt-sandbox] Installing packages: ${not_installed[*]}"
sudo "$REAL_COMMAND" "${pre_opts[@]}" install "${cmd_opts[@]}" "${not_installed[@]}"
