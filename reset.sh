#!/usr/bin/env bash
set -euo pipefail

# CCC Development Reset Script
# Use this to completely reset your CCC environment during development

echo "Resetting CCC development environment..."

confirm_reset() {
    echo "This will remove CCC containers, images, networks, config, installed files, and generated runtime files inside your courses directory."
    read -r -p "Continue with full CCC reset? [y/N] " REPLY
    case "$REPLY" in
        [yY]|[yY][eE][sS])
            ;;
        *)
            echo "Reset cancelled."
            exit 0
            ;;
    esac
}

confirm_reset

# Set up paths and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/share/utils.sh"
source "$SCRIPT_DIR/share/config.sh"

if [[ -f "$SCRIPT_DIR/share/container_helpers.sh" ]]; then
    source "$SCRIPT_DIR/share/container_helpers.sh"
else
    log_error "Missing share/container_helpers.sh"
    exit 1
fi

if [[ -f "$SCRIPT_DIR/share/cleanup.sh" ]]; then
    source "$SCRIPT_DIR/share/cleanup.sh"
else
    log_error "Missing share/cleanup.sh"
    exit 1
fi

# Detect container runtime
CONTAINER_RUNTIME=$(detect_container_runtime) || {
    log_error "No container runtime found"
    exit 1
}

log_info "Using container runtime: $CONTAINER_RUNTIME"

# 1. Stop and remove all CCC containers
log_info "Stopping and removing all CCC containers..."
local_ids=$($CONTAINER_RUNTIME ps -a --filter "name=ccc" --format "{{.Names}} {{.ID}}" 2>/dev/null) || true
if [[ -n "$local_ids" ]]; then
    while read -r name id; do
        if [[ -n "$name" ]]; then
            echo "  Removing container: $name ($id)"
            $CONTAINER_RUNTIME stop "$id" 2>/dev/null || true
            $CONTAINER_RUNTIME rm -f "$id" 2>/dev/null || true
        fi
    done <<< "$local_ids"
fi

# 2. Remove all CCC images
log_info "Removing all CCC images..."
local_ids=$($CONTAINER_RUNTIME images --filter "reference=ccc*" --format "{{.Repository}}:{{.Tag}} {{.ID}}" 2>/dev/null) || true
if [[ -n "$local_ids" ]]; then
    while read -r ref id; do
        if [[ -n "$ref" ]]; then
            echo "  Removing image: $ref ($id)"
            $CONTAINER_RUNTIME rmi -f "$id" 2>/dev/null || true
        fi
    done <<< "$local_ids"
fi

# 3. Remove CCC networks
log_info "Removing CCC networks..."
for net in "net-ccc" "net-cs-courses"; do
    if $CONTAINER_RUNTIME network inspect "$net" &>/dev/null; then
        echo "  Removing network: $net"
        $CONTAINER_RUNTIME network rm "$net" 2>/dev/null || true
    fi
done

# 4. Clean up configuration and course runtime files
log_info "Cleaning up CCC configuration and course runtime files..."

# Read courses directory from config before removing it
courses_dir=""
if [[ -f "$(get_config_file)" ]]; then
    load_config 2>/dev/null || true
    courses_dir="${CCC_COURSES_DIR:-${COURSES_DIR:-}}"
fi

# Remove generated CCC files from each course directory, but keep the
# configured courses directory and the course repositories themselves.
if [[ -n "$courses_dir" ]] && [[ -d "$courses_dir" ]]; then
    echo "  Cleaning generated CCC files under: $courses_dir"
    for course_dir in "$courses_dir"/*; do
        [[ -d "$course_dir" ]] || continue
        remove_course_runtime_files "$course_dir"
    done
elif [[ -d "./courses" ]]; then
    echo "  Cleaning generated CCC files under: ./courses"
    for course_dir in ./courses/*; do
        [[ -d "$course_dir" ]] || continue
        remove_course_runtime_files "$course_dir"
    done
fi

# Remove configuration file(s)
config_file="$(get_config_file)"
config_dir="$(dirname "$config_file")"
if [[ -f "$config_file" ]]; then
    echo "  Removing CCC configuration: $config_file"
    rm -f "$config_file"
    # Remove directory if empty
    rmdir "$config_dir" 2>/dev/null || true
fi

# 5. Clean up generated Dockerfiles
log_info "Cleaning up generated Dockerfiles..."
rm -f ./Dockerfile.generated.*

# 6. Clean up installed CCC if it exists
log_info "Cleaning up installed CCC..."
if [[ -d "$HOME/.local/share/ccc" ]]; then
    echo "  Removing $HOME/.local/share/ccc"
    rm -rf "$HOME/.local/share/ccc"
fi

if [[ -f "$HOME/.local/bin/ccc" ]]; then
    echo "  Removing $HOME/.local/bin/ccc"
    rm -f "$HOME/.local/bin/ccc"
fi

# Also check system-wide installation
if [[ -d "/usr/local/share/ccc" ]]; then
    echo "  Removing /usr/local/share/ccc (requires sudo)"
    sudo rm -rf "/usr/local/share/ccc" 2>/dev/null || echo "    Could not remove system installation (permission denied)"
fi

if [[ -f "/usr/local/bin/ccc" ]]; then
    echo "  Removing /usr/local/bin/ccc (requires sudo)"
    sudo rm -f "/usr/local/bin/ccc" 2>/dev/null || echo "    Could not remove system installation (permission denied)"
fi

# 7. Clean up any volumes (optional)
log_info "Cleaning up unused volumes..."
$CONTAINER_RUNTIME volume prune -f 2>/dev/null || true

# 8. System prune (optional)
log_info "Running system prune..."
$CONTAINER_RUNTIME system prune -f 2>/dev/null || true

echo ""
log_info "CCC development environment reset complete!"
echo ""
echo "To reinstall CCC:"
echo "  ./install.sh"
echo ""
echo "To start fresh:"
echo "  ccc open [course id]"

# Optional: Show current status
echo ""
log_info "Current status:"
echo "Containers: $($CONTAINER_RUNTIME ps -a --filter 'name=ccc' --format '{{.Names}}' | wc -l | tr -d ' ') CCC containers"
echo "Images: $($CONTAINER_RUNTIME images --filter 'reference=ccc*' --format '{{.Repository}}' | wc -l | tr -d ' ') CCC images"
echo "Networks: $($CONTAINER_RUNTIME network ls --filter 'name=ccc' --format '{{.Name}}' | wc -l | tr -d ' ') CCC networks"
