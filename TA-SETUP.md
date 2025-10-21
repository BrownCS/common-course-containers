# TA Course Setup Guide

Quick guide for TAs to set up courses in the CCC system.

## Required Files

Your course repo needs these two files:

### 1. `.envrc` (Environment Variables)
```bash
# Standard environment (don't change these)
export DEBIAN_FRONTEND=noninteractive
export TZ=America/New_York
export LANG=en_US.UTF-8
export PATH=$PWD/bin:$PATH

# Course-specific additions (customize below)
# export COURSE_VAR=value
# alias submit="./submit.sh"
# alias grade="python3 grader.py"

source_env setup/entrypoint.sh
```

### 2. `setup/entrypoint.sh` (Container Entry Script)
```bash
#!/bin/sh
set -e

version_file=/etc/image-version

echo "***************************************************************************************"
if [ -e "${version_file}" ]; then
  echo "Starting container: $(cat ${version_file})"
fi
echo "Course: YOUR_COURSE_NAME"
echo "Container IP: $(hostname --ip-address)"
echo "***************************************************************************************"

# Add any course-specific startup commands here
# echo "Welcome to CSCI-XXXX!"
# echo "Available commands: submit, test, grade"
```

## Setup Steps

1. **Copy template files** to your course repo
2. **Customize** the commented sections above
3. **Add to registry** (contact admin) with optional base image:
   ```
   your-course,https://github.com/yourorg/course-repo.git,Course Name,semester
   ```
4. **For custom base images** (optional):
   ```
   your-course,https://github.com/yourorg/course-repo.git,Course Name,semester,ubuntu:jammy
   ```

## Optional Additions

### Custom Scripts in `bin/`
Students get `./bin` in their PATH automatically:
```bash
mkdir bin
echo '#!/bin/bash\necho "Submitting..."' > bin/submit
chmod +x bin/submit
```

### VS Code Integration
Add this script to open current directory in VS Code from inside container:
```bash
#!/bin/bash
# bin/vscode - Open current directory in host VS Code
CONTAINER_NAME=$(podman ps --format '{{.Names}}' | grep ccc | head -1)
CURRENT_PATH="/courses/$(basename $PWD)"

if [ -n "$CONTAINER_NAME" ]; then
    # Signal host to open VS Code attached to this container
    echo "Opening VS Code on host for container: $CONTAINER_NAME"
    echo "Path: $CURRENT_PATH"

    # Method 1: Try direct host command execution
    podman exec --privileged "$CONTAINER_NAME" sh -c "
        echo 'code --folder-uri vscode-remote://attached-container+$CONTAINER_NAME$CURRENT_PATH' > /tmp/vscode_cmd
        nsenter -t 1 -m -p sh -c 'eval \$(cat /tmp/vscode_cmd)'
    " 2>/dev/null || echo "Run on host: code --folder-uri vscode-remote://attached-container+$CONTAINER_NAME$CURRENT_PATH"
else
    echo "No container found. Run 'ccc run <course>' first."
fi
```

### Course-Specific Aliases
Add to `.envrc`:
```bash
alias hw1="cd hw1 && code ."
alias test-hw1="cd hw1 && python3 test.py"
alias submit-hw1="cd hw1 && ./submit.sh"
```

### Setup Script (optional)
Add `setup.sh` for one-time course setup:
```bash
#!/bin/bash
# Install course-specific dependencies
# Create initial directories
# Download starter files
```

## Base Images

**Default**: Most courses use the shared Ubuntu container (leave base_image empty)

**Custom**: For specialized environments (databases, specific languages):
- `ubuntu:jammy` - Ubuntu 22.04
- `ubuntu:focal` - Ubuntu 20.04
- `python:3.11` - Python-focused
- `node:18` - Node.js environment

## Student Workflow

Students will:
1. `ccc setup your-course` (downloads your repo)
2. `cd courses/your-course` (direnv loads environment)
3. Work in assignment folders (`hw1/`, `project2/`, etc.)
4. Use your custom commands/aliases

## Testing

Test your setup:
```bash
# Test direnv
cd courses/your-course
direnv allow
echo $PATH  # Should show ./bin

# Test container
ccc run your-course
```

That's it! Students get a consistent environment with your customizations.