#!/usr/bin/env bash

# CCC (Common Course Containers) Installation Script
# Professional installation following Unix/Linux best practices

set -e # Exit on any error

# Load version from VERSION file
VERSION=$(cat "$(dirname "$0")/VERSION" 2>/dev/null || echo "unknown")
SCRIPT_NAME="$(basename "$0")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to user-local installation
INSTALL_MODE="user"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    --system)
        INSTALL_MODE="system"
        shift
        ;;
    --user)
        INSTALL_MODE="user"
        shift
        ;;
    --help | -h)
        echo "CCC Installation Script"
        echo "Usage: $SCRIPT_NAME [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --user     Install for current user only (default, no sudo needed)"
        echo "  --system   Install system-wide (requires sudo)"
        echo "  --help     Show this help message"
        echo ""
        echo "Examples:"
        echo "  $SCRIPT_NAME              # User-local install"
        echo "  $SCRIPT_NAME --user       # User-local install (explicit)"
        echo "  sudo $SCRIPT_NAME --system # System-wide install"
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
done

# Set installation paths based on mode
if [[ "$INSTALL_MODE" == "system" ]]; then
    BIN_DIR="/usr/local/bin"
    SHARE_DIR="/usr/local/share/ccc"
    SEARCH_PATH="/usr/local/share/ccc"
else
    BIN_DIR="$HOME/.local/bin"
    SHARE_DIR="$HOME/.local/share/ccc"
    SEARCH_PATH="$HOME/.local/share/ccc"
fi

MAIN_SCRIPT="$BIN_DIR/ccc"

# Source logging functions from utils
source "$REPO_DIR/lib/utils.sh"

# Check permissions based on installation mode
check_permissions() {
    if [[ "$INSTALL_MODE" == "system" ]]; then
        if [[ $EUID -ne 0 ]]; then
            log_error "System installation requires sudo privileges"
            echo "Usage: sudo $SCRIPT_NAME --system"
            echo ""
            echo "Alternatively, use user-local installation (no sudo needed):"
            echo "  $SCRIPT_NAME --user"
            exit 1
        fi
        log_info "Installing system-wide (requires sudo)"
    else
        if [[ $EUID -eq 0 ]]; then
            log_warning "Running as root for user installation"
            echo "Consider running without sudo for user-local install"
        fi
        log_info "Installing for user: $(whoami)"
    fi
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    # Check for podman
    if ! command -v podman >/dev/null 2>&1; then
        missing_deps+=("podman")
    fi

    # Check for git (used by courses)
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi

    # Check for direnv (used by courses)
    if ! command -v direnv >/dev/null 2>&1; then
        log_warning "direnv not found - course environments may not work properly"
        echo "  Install with: sudo apt install direnv  # or brew install direnv"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
            podman)
                echo "  Podman: https://podman.io/getting-started/installation"
                ;;
            git)
                echo "  Git: sudo apt install git  # or brew install git"
                ;;
            esac
        done
        exit 1
    fi

    log_success "All required dependencies found"
}

# Validate source files
validate_source() {
    log_info "Validating source files..."

    local required_files=(
        "ccc-host.sh"
        "lib/utils.sh"
        "lib/courses.sh"
        "lib/container.sh"
        "registry.csv"
        "Dockerfile.template"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$REPO_DIR/$file" ]]; then
            log_error "Required file not found: $file"
            echo "Make sure you're running this script from the CCC repository root"
            exit 1
        fi
    done

    log_success "All source files validated"
}

# Create directories
create_directories() {
    log_info "Creating installation directories..."

    mkdir -p "$BIN_DIR"
    mkdir -p "$SHARE_DIR"
    mkdir -p "$SHARE_DIR/lib"

    log_success "Installation directories created"
}

# Install files
install_files() {
    log_info "Installing CCC files..."

    # Copy main script
    cp "$REPO_DIR/ccc-host.sh" "$MAIN_SCRIPT"
    chmod +x "$MAIN_SCRIPT"

    # Copy library files
    cp "$REPO_DIR/lib/"*.sh "$SHARE_DIR/lib/"

    # Copy registry, VERSION file, and Dockerfile template
    cp "$REPO_DIR/registry.csv" "$SHARE_DIR/"
    cp "$REPO_DIR/VERSION" "$SHARE_DIR/"
    cp "$REPO_DIR/Dockerfile.template" "$SHARE_DIR/"

    # Script already has path detection built-in, no modification needed

    log_success "CCC files installed"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    # Check if ccc command works
    if ! "$MAIN_SCRIPT" --version >/dev/null 2>&1; then
        if ! "$MAIN_SCRIPT" >/dev/null 2>&1; then
            log_error "Installation verification failed - ccc command not working"
            exit 1
        fi
    fi

    # Check if supporting files are accessible
    if [[ ! -f "$SHARE_DIR/registry.csv" ]]; then
        log_error "Installation verification failed - supporting files not found"
        exit 1
    fi

    log_success "Installation verified successfully"
}

# Check and setup PATH for user installation
setup_user_path() {
    if [[ "$INSTALL_MODE" == "user" ]]; then
        # Check if ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            log_info "Adding ~/.local/bin to PATH..."

            # Detect shell and add to appropriate profile
            local shell_profile=""
            if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
                shell_profile="$HOME/.zshrc"
            elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == *"bash"* ]]; then
                shell_profile="$HOME/.bashrc"
            else
                # Default to .profile for compatibility
                shell_profile="$HOME/.profile"
            fi

            # Add PATH export if not already present
            if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$shell_profile" 2>/dev/null; then
                echo '' >>"$shell_profile"
                echo '# Added by CCC installer' >>"$shell_profile"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$shell_profile"
                log_success "Added ~/.local/bin to PATH in $shell_profile"
                echo ""
                echo -e "${YELLOW}Please restart your terminal or run:${RESET}"
                echo -e "  ${GREEN}source $shell_profile${RESET}"
            else
                log_info "PATH already configured in $shell_profile"
            fi
        else
            log_success "~/.local/bin already in PATH"
        fi
    fi
}

# Show post-install information
show_post_install_info() {
    log_success "CCC installation completed!"
    echo ""

    if [[ "$INSTALL_MODE" == "user" ]]; then
        echo "Installed to: $SHARE_DIR"
        echo "Command: $MAIN_SCRIPT"
        echo ""
        setup_user_path
    else
        echo "Installed system-wide to: $SHARE_DIR"
        echo ""
    fi

    echo "Next steps:"
    echo "1. Initialize your courses directory:"
    echo -e "   ${GREEN}ccc init${RESET}"
    echo ""
    echo "2. Setup a course:"
    echo -e "   ${GREEN}ccc setup <course-name>${RESET}"
    echo ""
    echo "3. Run a course container:"
    echo -e "   ${GREEN}ccc run <course-name>${RESET}"
    echo ""
    echo "4. View available courses:"
    echo -e "   ${GREEN}ccc${RESET} (shows usage and available courses)"
    echo ""
    echo -e "For help: ${GREEN}ccc --help${RESET} or check the documentation"
    echo ""
    echo "To uninstall: run the uninstall script from the repository"
}

# Main installation function
main() {
    echo "CCC (Common Course Containers) Installer v$VERSION"
    echo "=============================================="
    echo ""

    check_permissions
    validate_source
    check_dependencies
    create_directories
    install_files
    verify_installation
    show_post_install_info
}

# Run main function
main "$@"
