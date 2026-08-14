# CCC (Common Course Configuration)

CCC is a course environment management tool meant to reduce setup time and streamline assignment completion for CS students. It currently supports computer science courses that require container-based environments and is being extended to support courses with other development environment needs. This README details how to use the tool as a student

## Quick Start

```bash
# Install the CCC tool
./install.sh

# Setup courses directory and select auto-update preferences
ccc init

# Open a course environment
ccc open <course-id> --> ex: ccc open csci-1515-demo
```

## Requirements

- **Podman** (required)
- **Git** (required)

## Commands

### Course Management
- `ccc list <--avail or --installed>` <- List ccc supported courses or your installed courses
- `ccc open <course-id> <OPTIONAL: --skip-installer>` - Open course environment. Use flag --skip-installer to skip CCC managed installer
- `ccc cleanup <course-id` - Clean up all resources associated with course environment

### Container Management
- `ccc status <course-id>` - Show container/course status (omit course for default/shared container info)
- `ccc cleanup <course-id>` - Clean up all resources associated with course environment

### Tool Management
- `ccc auto-update <status, enable, disable>` - View, enable, and disable auto-update preferences
- `ccc init` - Setup courses directory and initial auto update preference
- `ccc upgrade <--user, --system, --help>` - Upgrade the CCC tool (defaults to --user if no flag given)
- `ccc config get [config var]` - Get the value of a CCC configuration variable
- `ccc config set [config var] [config value]` - Set the value of a CCC configuration variable

## Options

- `--help, -h` - Show help
- `--version` - Show ccc version

## Installation

**User-local (default):**
```bash
./install.sh
```

**System-wide:**
```bash
sudo ./install.sh --system
```

**Reset/Clear CCC Generated Resources**
```bash
./reset.sh
```

**Uninstall:**
```bash
./uninstall.sh
```

## How It Works (very brief, see DOCS.md and TA-SETUP for more details)

1. **Course registry** (`registry.csv`) defines available courses, links their developement repos, and lists their requirements (container, architecture, etc)
2. **CCC** (`bin/ccc`) is the central dispatch for all CCC commands, loads necessary helper files and environment variables needed for course setup
3. **Open** (share/open.sh) houses the logic that determines how a course will be opened (based on registry, either container or local shell), then opens the appropriate environment
4. `share/course_installer.sh` is the installer used to download course specific packages, generate symlinks, and load environment variables into the shared/default CCC container. This facilitates multiple courses using the same, shared container provided by CCC.

## License
TBD

