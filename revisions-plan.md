# CCC Revisions Plan

## Current status

- Milestones 1-2 are effectively complete: config/registry basics and the top-level CLI dispatcher are in place.
- Milestone 3 is mostly complete: `ccc open` exists, course directories are managed separately, and sessions are tracked.
- Milestone 4 is the main in-progress area: container flow is registry-driven and uses the standardized course installer manifests.
- Milestone 5 is partially reframed: user-facing `ccc close` is no longer the goal; cleanup should happen automatically when the user exits the shell.
- Milestones 6-8 are still ahead of us.

## Current design decisions

- We no longer use per-course `setup.sh` scripts.
- Courses provide three manifest files instead: `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt`.
- CCC performs the setup itself by reading those manifests through the course installer.
- `ccc open` should not require user-facing flags for the core flow.
- `direnv` is no longer part of the design.
- The old host-mode-vs-container-mode split is being collapsed into one registry-driven `ccc open` flow.
- There is no user-facing `ccc close` command in the intended workflow; the shell exit path is responsible for cleanup.

## Installation and location

CCC is still bootstrapped with `./install.sh` during development. The plan remains to keep the CCC tool location separate from the courses directory.

- CCC installs to a tool location under the user's control or the default install prefix.
- The courses directory defaults to a separate path such as `~/courses`.
- The installer and `ccc init` are responsible for creating or recording the user's config.
- The main user choice that matters is the courses directory.

## Running a course environment with CCC

The command is a single `ccc open [course]` flow. It works like this:

1. Check whether `[course]` exists in the registry.
2. Read `requires_container` from registry metadata to decide local vs container.
3. Ensure the course directory exists and clone or update the course repo if needed.
4. If a container is required, start or reuse the container.
5. Run the standardized course installer, which reads `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt`.
6. Open the course shell and leave the user in the environment.

## Closing or switching courses

Closing a course should happen when the user exits the shell. Cleanup should remove session state and clear the managed-environment marker automatically. Switching courses should close the current one, clean it up, and then open the new course.

## Cleanup and advanced commands

Cleanup still needs to be reworked so CCC-managed containers, images, and networks can be removed cleanly.

Planned advanced commands:

1. `ccc config` for changing the courses directory and other settings
2. `ccc uninstall` for removing CCC-managed files and container artifacts
3. `ccc remove [target]` for removing containers, images, or networks
4. Legacy command names like `ccc setup`, `ccc update`, and `ccc upgrade` may remain as compatibility wrappers, but they should not be the primary workflow
5. `ccc list` should eventually distinguish available vs installed courses
6. An archive flag for `ccc open` remains optional/future

## Default architecture and environment management

Container images should default to the machine's native architecture. CCC now opens courses in a new shell with the proper environment, so it can manage PATH and other variables directly.

## Host mode vs container mode

This tool is no longer something that always starts a container. Some courses will open locally, while others require a container. The command should choose behavior based on registry metadata, but the user-facing surface should stay unified under `ccc open`.

## Milestones

### Milestone 0 - Project hygiene
- Add optional contributor and conduct docs.
- Add a short developer README section describing the code layout.

### Milestone 1 - Config and registry basics
- `lib/config.sh` for cross-platform config lookup and read/write helpers.
- `lib/registry.sh` for registry parsing.
- Document config keys and registry columns.

### Milestone 2 - CLI dispatcher and basic commands
- `ccc.sh` as the top-level dispatcher.
- `ccc config` get/set.
- `ccc list` basic outputs.
- `install.sh` writes initial config if missing.

### Milestone 3 - `ccc open` foundation
- `ccc open` ensures course directories exist and opens the correct shell.
- Session tracking via `session.json` in the config dir.
- Basic tests for the local open path.

### Milestone 4 - Container integration and labels
- Container helpers for Docker/Podman.
- Registry-driven `requires_container` selection.
- Run the standardized course installer inside the container.
- Keep containers ephemeral by default, with reuse controlled in config.

### Milestone 5 - Exit-based cleanup and lifecycle handling
- Terminate sessions cleanly when the shell exits.
- Clear managed-environment state automatically on exit.
- Remove CCC-managed containers/images/networks through explicit cleanup commands, not `ccc close`.
- Preserve compatibility with any legacy references only where needed for transition.

### Milestone 6 - Update checks and UX polish
- Define update policy for git-installed vs packaged installs.
- Prompt during setup for whether automatic update checks are enabled.
- Keep package-manager installs from auto-updating themselves.

### Milestone 7 - Backward compatibility and cleanup
- Remove old `setup.sh` assumptions from helper paths and documentation.
- Remove duplicate host/container code paths.
- Align docs and tests with the manifests-first course contract.

### Milestone 8 - Packaging
- Packaging recipes for deb/rpm/Homebrew.
- Post-install hooks that call the same init logic as `ccc init`.

## Where we are now

We are around Milestone 4, with some Milestone 5 behavior already starting to appear in the open/session cleanup flow. The main remaining work is container polish, exit-based cleanup, and then the later lifecycle commands.
