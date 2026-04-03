# CCC (Common Course Containers)

Container-based environment management for computer science courses.

## Quick Start

```bash
# Install
./install.sh

# Setup courses directory
ccc init

# Setup a course
ccc setup csci-0300-demo

# Run shared container
ccc run default
```

## Course specific containers

You can also run the course specific container in this manner.

```
# Run course container
ccc run csci-0300-demo
```

## Requirements

- **Podman** (required)
- **Git** (required)

## Commands

### Course Management
- `ccc list` - List installed courses
- `ccc setup <course>` - Clone and setup course
- `ccc update <course>` - Update course repository
- `ccc run <course>` - Start/attach to course container

### Container Management
- `ccc build` - Build container image
- `ccc clean [containers|images|networks|all]` - Clean resources
- `ccc status` - Show container status

### Tool Management
- `ccc init` - Setup courses directory
- `ccc upgrade` - Upgrade CCC tool

## Options

- `--verbose, -v` - Show detailed output
- `--help, -h` - Show help

## Installation

**User-local (default):**
```bash
./install.sh
```

**System-wide:**
```bash
sudo ./install.sh --system
```

**Uninstall:**
```bash
./uninstall.sh
```

## How It Works

1. **Course registry** (`registry.csv`) defines available courses
2. **Setup** clones course repos and runs setup scripts
3. **Containers** provide isolated, consistent environments
4. **direnv** manages per-course environment variables

## Development

Run from source directory:
```bash
./ccc-host.sh <command>
```

## License

