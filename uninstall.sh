#!/usr/bin/env bash

# CCC (Common Course Containers) Uninstallation Script
# Removes CCC system installation

set -e # Exit on any error

# Load version from VERSION file (for display purposes)
VERSION=$(cat "$(dirname "$0")/VERSION" 2>/dev/null || echo "unknown")
SCRIPT_NAME="$(basename "$0")"

# Detect installation type
USER_BIN_DIR="$HOME/.local/bin"
USER_SHARE_DIR="$HOME/.local/share/ccc"
SYSTEM_BIN_DIR="/usr/local/bin"
SYSTEM_SHARE_DIR="/usr/local/share/ccc"

# Auto-detect installation type
if [[ -f "$USER_BIN_DIR/ccc" ]] || [[ -d "$USER_SHARE_DIR" ]]; then
    INSTALL_MODE="user"
    BIN_DIR="$USER_BIN_DIR"
    SHARE_DIR="$USER_SHARE_DIR"
elif [[ -f "$SYSTEM_BIN_DIR/ccc" ]] || [[ -d "$SYSTEM_SHARE_DIR" ]]; then
    INSTALL_MODE="system"
    BIN_DIR="$SYSTEM_BIN_DIR"
    SHARE_DIR="$SYSTEM_SHARE_DIR"
else
    INSTALL_MODE="unknown"
    BIN_DIR=""
    SHARE_DIR=""
fi

MAIN_SCRIPT="$BIN_DIR/ccc"

# Source logging functions from utils
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/share/utils.sh"
source "$REPO_DIR/share/config.sh"

# Check permissions based on detected installation
check_permissions() {
    if [[ "$INSTALL_MODE" == "system" ]]; then
        if [[ $EUID -ne 0 ]]; then
            log_error "System installation detected - sudo required for uninstall"
            echo "Usage: sudo $SCRIPT_NAME"
            exit 1
        fi
        log_info "Uninstalling system-wide installation"
    elif [[ "$INSTALL_MODE" == "user" ]]; then
        log_info "Uninstalling user-local installation"
    else
        log_info "No CCC installation detected"
    fi
}

# Check if CCC is installed
check_installation() {
    if [[ ! -f "$MAIN_SCRIPT" ]] && [[ ! -d "$SHARE_DIR" ]]; then
        log_warning "CCC does not appear to be installed (no files found)"
        echo "Installation paths checked:"
        echo "  $MAIN_SCRIPT"
        echo "  $SHARE_DIR"
        exit 0
    fi
}

# Confirm uninstallation
confirm_uninstall() {
    echo "CCC (Common Course Containers) Uninstaller v$VERSION"
    echo "====================================================="
    echo ""
    log_warning "This will remove CCC from your system"
    echo ""
    echo "Files to be removed:"
    [[ -f "$MAIN_SCRIPT" ]] && echo "  $MAIN_SCRIPT"
    [[ -d "$SHARE_DIR" ]] && echo "  $SHARE_DIR"
    echo ""
    log_info "Course directories and containers will NOT be removed"
    echo ""

    read -p "Continue with uninstallation? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
}

# Remove installed files
remove_files() {
    log_info "Removing CCC files..."

    # Remove main script
    if [[ -f "$MAIN_SCRIPT" ]]; then
        rm -f "$MAIN_SCRIPT"
        log_success "Removed $MAIN_SCRIPT"
    fi

    # Remove share directory
    if [[ -d "$SHARE_DIR" ]]; then
        rm -rf "$SHARE_DIR"
        log_success "Removed $SHARE_DIR"
    fi

    # Remove shell PATH edits added by the installer for user-local installs.
    if [[ "$INSTALL_MODE" == "user" ]]; then
        local shell_profile=""
        if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
            shell_profile="$HOME/.zshrc"
        elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == *"bash"* ]]; then
            shell_profile="$HOME/.bashrc"
        else
            shell_profile="$HOME/.profile"
        fi

        if [[ -f "$shell_profile" ]]; then
            local tmp_profile="${shell_profile}.ccc-uninstall"
            awk '
                BEGIN { skip = 0 }
                /^# Added by CCC installer$/ { skip = 1; next }
                skip == 1 && /^export PATH="\$HOME\/\.local\/bin:\$PATH"$/ { skip = 0; next }
                { print }
            ' "$shell_profile" >"$tmp_profile" && mv "$tmp_profile" "$shell_profile"
            log_success "Removed CCC PATH entry from $shell_profile"
        fi

        # Remove configuration files from both the resolved CCC config directory
        # and the legacy ~/.config/ccc location used by older installs.
        local cfg_dirs=("$(resolve_config_dir)" "$HOME/.config/ccc")
        local cfg_dir=""
        local removed_config=false
        for cfg_dir in "${cfg_dirs[@]}"; do
            if [[ -n "$cfg_dir" ]] && [[ -d "$cfg_dir" ]]; then
                rm -f "$cfg_dir/config" "$cfg_dir/settings" "$cfg_dir/default-container-courses.txt"
                rmdir "$cfg_dir" 2>/dev/null || true
                removed_config=true
            fi
        done
        if [[ "$removed_config" == true ]]; then
            log_success "Removed CCC configuration"
        fi
    fi
}

# Verify removal
verify_removal() {
    log_info "Verifying uninstallation..."

    if [[ -f "$MAIN_SCRIPT" ]] || [[ -d "$SHARE_DIR" ]]; then
        log_error "Uninstallation incomplete - some files remain"
        exit 1
    fi

    log_success "CCC completely removed from system"
}

# Show post-uninstall information
show_post_uninstall_info() {
    log_success "CCC uninstallation completed!"
    echo ""
    if [[ "$INSTALL_MODE" == "user" ]]; then
        echo "What was removed:"
        echo "• CCC executable and files"
        echo "• CCC configuration"
        echo ""
        echo "What was NOT removed (if you want to clean these up manually):"
        echo "• Course directories (user data)"
        echo "• Podman containers and images"
    else
        echo "What was NOT removed (if you want to clean these up manually):"
        echo "• Course directories (user data)"
        echo "• User configurations (per-user)"
        echo "• Podman containers and images"
    fi
    echo ""
    echo "To completely clean up CCC-related containers and images:"
    echo -e "  ${GREEN}podman ps -a | grep ccc${RESET}      # List CCC containers"
    echo -e "  ${GREEN}podman images | grep ccc${RESET}     # List CCC images"
    echo -e "  ${GREEN}podman system prune${RESET}          # Clean up unused resources"
    echo ""
    echo "To reinstall CCC, run the install script from the repository"
}

# Main uninstallation function
main() {
    check_permissions
    check_installation
    confirm_uninstall
    remove_files
    verify_removal
    show_post_uninstall_info
}

# Run main function
main "$@"
