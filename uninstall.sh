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
source "$REPO_DIR/lib/utils.sh"

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

    # Handle courses directory and configuration
    local courses_dir=""
    if [[ "$INSTALL_MODE" == "user" ]] && [[ -f "$HOME/.config/ccc/config" ]]; then
        # Read courses directory from config
        source "$HOME/.config/ccc/config" 2>/dev/null || true
        courses_dir="${COURSES_DIR:-}"

        # Ask user about courses directory
        if [[ -n "$courses_dir" ]] && [[ -d "$courses_dir" ]]; then
            echo ""
            log_warning "Found courses directory: $courses_dir"
            echo "This contains your course files and data."
            read -p "Remove courses directory? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$courses_dir"
                log_success "Removed courses directory: $courses_dir"
            else
                log_info "Kept courses directory: $courses_dir"
            fi
        fi

        # Remove configuration files
        rm -f "$HOME/.config/ccc/config"
        rm -f "$HOME/.config/ccc/settings"
        # Remove directory if empty
        rmdir "$HOME/.config/ccc" 2>/dev/null || true
        log_success "Removed CCC configuration"
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
        echo "• CCC configuration (~/.config/ccc/config)"
        echo ""
        echo "What was NOT removed (if you want to clean these up manually):"
        echo "• Course directories (user data)"
        echo "• Podman containers and images"
    else
        echo "What was NOT removed (if you want to clean these up manually):"
        echo "• Course directories (user data)"
        echo "• User configurations in ~/.config/ccc/ (per-user)"
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
