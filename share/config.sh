 #!/usr/bin/env sh
# Simple config helpers for CCC
# - resolve_config_dir: determine config directory
# - load_config: source key=value config file
# - set_config: set a key in the config file
# - prompt_init: interactive first-run setup (writes default keys)

resolve_config_dir() {
    # Prefer XDG, then macOS, then APPDATA (Windows), then fallback
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        CONFIG_DIR="$XDG_CONFIG_HOME/ccc"
    else
        uname_s=$(uname 2>/dev/null || true)
        case "$uname_s" in
        Darwin)
            CONFIG_DIR="$HOME/Library/Application Support/ccc"
            ;;
        *)
            if [ -n "${APPDATA:-}" ]; then
                CONFIG_DIR="$APPDATA/ccc"
            else
                # fallback
                CONFIG_DIR="$HOME/.ccc"
            fi
            ;;
        esac
    fi

    # Ensure directory exists
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR" || return 1
    fi

    echo "$CONFIG_DIR"
}

get_config_file() {
    CONFIG_DIR=$(resolve_config_dir) || return 1
    echo "$CONFIG_DIR/config"
}

load_config() {
    cfg=$(get_config_file) || return 1
    if [ -f "$cfg" ]; then
        # shellcheck disable=SC1090
        . "$cfg"
    fi
}

set_config() {
    # set_config KEY VALUE
    key=$1
    value=$2
    cfg=$(get_config_file) || return 1

    # Ensure file exists
    touch "$cfg" || return 1
    # Remove existing key and append new key=value
    # Use temporary file
    tmp="$cfg.tmp"
    grep -v -E "^${key}=" "$cfg" 2>/dev/null >"$tmp" || true
    printf '%s="%s"\n' "$key" "$value" >>"$tmp"
    mv "$tmp" "$cfg"
    chmod 600 "$cfg" 2>/dev/null || true
}

prompt_init() {
    # Interactive init: set CCC_COURSES_DIR and CCC_AUTO_UPDATE
    echo "Initializing CCC configuration..."
    default_courses="$HOME/courses"
    printf 'Courses directory [%s]: ' "$default_courses"
    read -r courses_dir
    if [ -z "$courses_dir" ]; then
        courses_dir="$default_courses"
    fi

    printf 'Enable automatic ccc updates on open? (y/N): '
    read -r ans
    case "$ans" in
    [yY]|[yY][eE][sS])
        auto_update=true
        ;;
    *)
        auto_update=false
        ;;
    esac

    # Write defaults
    set_config CCC_INSTALL_MODE git
    set_config CCC_COURSES_DIR "$courses_dir"
    set_config CCC_AUTO_UPDATE "$auto_update"
    set_config CCC_CONTAINER_REUSE false

    echo "Wrote configuration to $(get_config_file)"
}
