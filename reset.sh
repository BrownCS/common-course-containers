#!/usr/bin/env bash
set -euo pipefail

# CCC Development Reset Script
# Use this to completely reset your CCC environment during development

echo "Resetting CCC development environment..."

# Set up paths and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/utils.sh"

if [[ -f "$SCRIPT_DIR/lib/container.sh" ]]; then
    source "$SCRIPT_DIR/lib/container.sh"
else
    # Fallback container runtime detection
    detect_container_runtime() {
        if command -v podman >/dev/null 2>&1; then
            echo "podman"
        elif command -v docker >/dev/null 2>&1; then
            echo "docker"
        else
            log_error "No container runtime found (podman/docker)"
            return 1
        fi
    }
fi

# Detect container runtime
CONTAINER_RUNTIME=$(detect_container_runtime)
if [[ $? -ne 0 ]]; then
    exit 1
fi

log_info "Using container runtime: $CONTAINER_RUNTIME"

# 1. Stop and remove all CCC containers
log_info "Stopping and removing all CCC containers..."
$CONTAINER_RUNTIME ps -a --filter "name=ccc" --format "{{.Names}} {{.ID}}" | while read name id; do
    if [[ -n "$name" ]]; then
        echo "  Removing container: $name ($id)"
        $CONTAINER_RUNTIME stop "$id" 2>/dev/null || true
        $CONTAINER_RUNTIME rm -f "$id" 2>/dev/null || true
    fi
done

# Also remove old cs-courses containers if they exist
$CONTAINER_RUNTIME ps -a --filter "name=cs-courses" --format "{{.Names}} {{.ID}}" | while read name id; do
    if [[ -n "$name" ]]; then
        echo "  Removing old container: $name ($id)"
        $CONTAINER_RUNTIME stop "$id" 2>/dev/null || true
        $CONTAINER_RUNTIME rm -f "$id" 2>/dev/null || true
    fi
done

# 2. Remove all CCC images
log_info "Removing all CCC images..."
$CONTAINER_RUNTIME images --filter "reference=ccc*" --format "{{.Repository}}:{{.Tag}} {{.ID}}" | while read ref id; do
    if [[ -n "$ref" ]]; then
        echo "  Removing image: $ref ($id)"
        $CONTAINER_RUNTIME rmi -f "$id" 2>/dev/null || true
    fi
done

# Also remove old cs-courses images
$CONTAINER_RUNTIME images --filter "reference=cs-courses*" --format "{{.Repository}}:{{.Tag}} {{.ID}}" | while read ref id; do
    if [[ -n "$ref" ]]; then
        echo "  Removing old image: $ref ($id)"
        $CONTAINER_RUNTIME rmi -f "$id" 2>/dev/null || true
    fi
done

# 3. Remove CCC networks
log_info "Removing CCC networks..."
for net in "net-ccc" "net-cs-courses"; do
    if $CONTAINER_RUNTIME network inspect "$net" &>/dev/null; then
        echo "  Removing network: $net"
        $CONTAINER_RUNTIME network rm "$net" 2>/dev/null || true
    fi
done

# 4. Clean up configuration and courses directory
log_info "Cleaning up CCC configuration and courses..."

# Remove configuration file
if [[ -f "$HOME/.config/ccc/config" ]]; then
    echo "  Removing CCC configuration: $HOME/.config/ccc/config"
    rm -f "$HOME/.config/ccc/config"
    # Remove directory if empty
    rmdir "$HOME/.config/ccc" 2>/dev/null || true
fi

# Remove local courses directory (common case)
if [[ -d "./courses" ]]; then
    echo "  Removing ./courses directory"
    rm -rf "./courses"
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
echo "  ccc init"
echo "  ccc run default"

# Optional: Show current status
echo ""
log_info "Current status:"
echo "Containers: $($CONTAINER_RUNTIME ps -a --filter 'name=ccc' --format '{{.Names}}' | wc -l | tr -d ' ') CCC containers"
echo "Images: $($CONTAINER_RUNTIME images --filter 'reference=ccc*' --format '{{.Repository}}' | wc -l | tr -d ' ') CCC images"
echo "Networks: $($CONTAINER_RUNTIME network ls --filter 'name=ccc' --format '{{.Name}}' | wc -l | tr -d ' ') CCC networks"
