# CCC Architecture

CCC is a host-side CLI that manages course-specific container environments using Podman. The architecture is intentionally simple:

- the host runs the `ccc` command
- a course repo is cloned under the configured courses directory
- the runtime either reuses a shared default container or starts a course-specific container image
- a small installer runs inside the container to install the course dependencies and create per-course symlinks

This document describes the current architecture as implemented in the repository today. There are plans to extend CCC to support non-container courses.

## 1. High-level model

There are two important runtime layers:

1. Host layer
   - shell entry point: `bin/ccc`
   - config and lifecycle helpers: `share/config.sh`, `share/utils.sh`
   - course registry and discovery: `share/registry.sh`, `share/courses.sh`
   - runtime helpers: `share/container_helpers.sh`, `share/open.sh`, `share/cleanup.sh`

2. Container layer
   - a Podman container is created for each course or shared default container
   - the mounted course directory is exposed at `/courses`
   - a course installer runs at `/usr/local/share/ccc/course_installer.sh`
   - the user lands in a bash shell with the course directory set as working dir

## 2. Main CCC Entry Point

All CCC commands go through `bin/ccc`. It sources most of the share directory and then dispatches the following commands:

- `ccc init`
- `ccc open <course>`
- `ccc cleanup <course>`
- `ccc status [course]`
- `ccc list [--avail|--installed]`
- `ccc config get|set`
- `ccc upgrade [--user|--system]`

## 3. Config model

CCC keeps a single config file that holds variables/settings and user defined preferences necessary to run CCC. These include, but are not limited to 
`CCC_COURSES_DIR`, `CCC_AUTO_UPDATE`, `CCC_UPDATE_REPO`. It lives in one of the following locations:

- XDG config home if present
- otherwise macOS Application Support
- otherwise a fallback under `$HOME/.ccc`


## 4. Registry and course type model

Course metadata lives in:

- `share/registry.csv`

Each row describes whether the course uses:

- a shared default container (`image_mode=default`), or
- a course-specific image (`image_mode=course-specific`)

This distinction is important:

- default container mode reuses one shared runtime for multiple courses
- course-specific mode uses an image dedicated to that course and generally skips the general installer

The registry also defines:

- repo URL
- course name
- semester / metadata
- container architecture
- whether the course requires a container

## 5. Default container tracking

Shared default-container usage is tracked by the host, not by the container itself.

The tracking file is managed in:

- `share/session.sh`

It stores which courses are currently associated with the shared default container. This matters because cleanup needs to know whether deleting the default container would affect other courses.

The logic looks like this:

- if a course uses the default container, it is recorded in the default-container tracking file
- `ccc open` for a default-mode course adds it to that list
- `ccc cleanup` for a default-mode course removes the tracking entry and may prompt to delete the shared default runtime if no other courses depend on it

## 6. Open flow

The runtime entry point is `ccc open <course>`.

The flow is:

1. Validate the course exists in the registry.
2. Ensure the course checkout exists under the configured courses directory.
3. Clone or update the Git checkout if needed.
4. Decide whether the course requires a container.
5. Start or reuse the correct container.
6. Run the installer inside the container.
7. Attach the user to a bash shell in the course directory.

The main orchestration lives in:

- `share/open.sh`

Key functions:

- `sync_course_checkout()`
- `start_container_for_course()`
- `ccc_open()`
- `build_course_shell_command()`
- `build_skip_installer_shell_command()`

The shell-launch command is responsible for setting up the runtime environment for the course. It does things like:

- `cd` into the course directory
- load the generated course env file when present
- export `CCC_MANAGED_ENV=true`
- export `CCC_COURSES_DIR`
- set `npm_config_cache=/tmp/.npm-cache` to avoid stale root-owned npm state
- run `bash -l`

The two shell-builder helpers exist because skip-installer mode is intentionally different from normal open mode. In skip mode, the installer may have been intentionally bypassed, so the shell should not assume the full installer-generated environment is ready.

## 7. Container startup logic

Container creation and reuse is centralized in:

- `share/container_helpers.sh`

The key responsibilities are:

- detect Podman (`detect_container_runtime`)
- create or reuse a network
- build or reuse an image
- set the workdir and mounted course path
- map the host user to the container user (`keep-id` semantics)
- inject environment variables like `DISPLAY` where relevant
- set memory-swap behavior to avoid exit code 137 from OOM kills during heavy package install steps

The shared default container uses a standard container name like `default`, while course-specific containers use course-aware names derived from the registry entry.

## 8. Installer behavior

The installer is a minimal shell script that runs inside the container:

- `share/course_installer.sh`

It is not a general package manager orchestrator; it is a course-specific setup tool. It:

- reads `setup/packages.txt`
- installs any missing packages with `apt-get`
- repairs interrupted package-manager state if needed
- discovers binaries installed by those packages
- creates symlinks into the course-local bin directories
- processes `setup/links.txt`
- writes necessary course environment variables to `env/course.env`
- writes a link manifest for cleanup and later diffing

The installer is intentionally conservative: it avoids broad rebuilds or expensive discovery work unless necessary.

## 9. Cleanup model

Cleanup is intentionally explicit and safe.

The orchestration path is:

- `share/cleanup.sh`

Cleanup does a few things:

- remove course runtime files from the course directory
- remove container state for the course
- remove image state for the course, if applicable
- untrack default-container usage for a course
- if the shared default container is still in use by other courses, prompt before deleting it

This is designed to avoid deleting a shared default container while other courses still depend on it.

## Upgrading CCC

The installer supports user or system upgrade mode:

- `ccc upgrade`
- `ccc upgrade --user`
- `ccc upgrade --system`

The logic lives in:

- `share/utils.sh`

It does the following:

- checks the current repo version
- fetches the latest GitHub release version
- downloads the release tarball
- runs the fresh installer in the matching mode

This is a self-update path for the host CLI itself, not a course update.

## Lifecycle summary

The current lifecycle looks like this:

```text
install.sh
  -> copies CLI + support scripts into the install prefix

ccc init
  -> confirms or sets CCC_COURSES_DIR and update preferences

ccc open csci-1515-demo
  -> validates registry
  -> clones/updates repo
  -> starts/reuses container
  -> runs installer
  -> drops user into a course shell

ccc cleanup csci-1515-demo
  -> removes course runtime files
  -> untracks default-container usage if relevant
  -> optionally removes shared default container if no longer needed
```
