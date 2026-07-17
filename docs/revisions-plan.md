# CCC Revisions Plan

## Current status

- Milestones 1-2 are effectively complete: config/registry basics and the top-level CLI dispatcher are in place.
- Milestone 3 is mostly complete: `ccc open` exists, course directories are managed separately, and sessions are tracked.
- Milestone 4 is mostly complete: container flow is registry-driven, uses the standardized course installer manifests, and supports course-specific images.
- Milestone 5 is actively in progress: shell-exit cleanup exists, and `ccc cleanup [course]` now removes a course's runtime state without touching the repo checkout.
- Course installation/update behavior is the next detail to tighten: setup should be checked against installed state, starting with package presence.
- Milestone 7 cleanup work has started: the explicit cleanup command is now split into its own module, and shared session helpers have been extracted.
- Milestones 6 and 8 are still ahead of us.

## Current design decisions

- We no longer use per-course `setup.sh` scripts.
- Courses provide three manifest files instead: `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt`.
- CCC performs the setup itself by reading those manifests through the course installer.
- CCC should verify whether the requested course setup is already present before skipping work; the installed state is the source of truth.
- `ccc open` should not require user-facing flags for the core flow.
- Containers are treated as reusable runtime environments when possible; course-specific setup is applied idempotently via the installer manifests.
- `direnv` is no longer part of the design.
- The old host-mode-vs-container-mode split is being collapsed into one registry-driven `ccc open` flow.
- There is no user-facing `ccc close` command in the intended workflow; shell exit is the primary lifecycle boundary.
- The session file is optional bookkeeping for recovery/debugging and is not the source of truth for course state.

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

Exiting a course shell should trigger cleanup automatically. Cleanup should clear the managed-environment marker and remove any active session metadata if present. Switching courses should reuse or replace the runtime as needed, but should not depend on a user-facing close command.

## Cleanup and advanced commands

Cleanup is now split into two layers: `ccc cleanup [course]` handles course-scoped runtime reset, while broader `ccc remove` and `ccc uninstall` remain for later container/image/install cleanup.

Course setup should follow the same shape: compare what the course manifest asks for to what is already installed, and rerun only the portions that are missing or out of date. That keeps updates visible when a course repository adds or removes packages, links, or environment variables.

Course setup checklist:

1. Read the current `setup/packages.txt`, `setup/links.txt`, and `setup/env.txt` files from the course repo.
2. Check whether each requested package is already installed before trying to install it.
3. Create or refresh the requested symlinks only when they are missing or point somewhere wrong.
4. Re-emit the generated environment file every time the course opens so env changes are always current.
5. Treat the course repo as the source of truth for requested state.
6. Re-run the relevant setup steps whenever the manifests change, even if the course has been opened before.
7. Keep cleanup separate: it should remove generated runtime state, not the course repository itself.

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
- `share/config.sh` for cross-platform config lookup and read/write helpers.
- `share/registry.sh` for registry parsing.
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
- Make shell exit the primary lifecycle boundary for course environments.
- Clear managed-environment state automatically on exit.
- Remove any active session metadata when the shell exits, without relying on a separate `ccc close` command.
- Support container reuse by matching the runtime to the requested course and applying setup idempotently.
- Replace the old setup gate with direct installed-state checks so changes in `packages.txt`, `links.txt`, or `env.txt` trigger the right update work.
- Preserve compatibility with any legacy references only where needed for transition.

### Milestone 7 - Backward compatibility and cleanup
- Keep `ccc cleanup [course]` scoped to course runtime state only.
- Keep shared lifecycle helpers factored so `open` and `cleanup` can reuse session and course-state logic.
- Make the installer compare installed package/link/env state to the current manifests.
- Remove old `setup.sh` assumptions from helper paths and documentation.
- Remove duplicate host/container code paths.
- Align docs and tests with the manifests-first course contract.

### Milestone 6 - Update checks and UX polish
- Define update policy for git-installed vs packaged installs.
- Prompt during setup for whether automatic update checks are enabled.
- Keep package-manager installs from auto-updating themselves.

### Milestone 8 - Packaging
- Packaging recipes for deb/rpm/Homebrew.
- Post-install hooks that call the same init logic as `ccc init`.

## Where we are now

We are now between Milestones 5 and 7: the core course-open path is in place, shell-exit cleanup works, and `ccc cleanup [course]` is available for course-scoped resets. The next design step is to make course setup update-aware by checking installed state directly, so package additions and manifest changes are picked up immediately.

## Steps Left To Finish

The remaining work is smaller than the work already done, but it matters for making CCC feel finished and safe for students and instructors.

### 1. Finish `ccc cleanup` for shared default containers

- Keep the current behavior for course-specific courses: remove the course container, image, and generated install/runtime files.
- Add tracking for default-container courses so CCC knows which course checkouts currently depend on the shared default container.
- On first open of a default-container course, record that course id in CCC-managed state.
- On `ccc cleanup [course]`, remove that course id from the tracked default-container list.
- If the cleaned course was the last default-container user, prompt before deleting the shared default container.
- If there are still tracked default-container courses, prompt before deleting the shared default container and the remaining generated course files.
- If the user declines, keep the shared container and the remaining shared-course files intact.
- If the default-container list is empty, still prompt before deleting the container so cleanup remains user-controlled.

### 2. Tighten update behavior for opened courses

- Keep `ccc open` responsible for cloning a missing course checkout.
- Reopen behavior should update existing git checkouts when auto-update is enabled, or prompt the user when it is not.
- Make manifest changes visible on reopen so package, link, and env updates are picked up without manual repo surgery.

### 3. Finish the manifests-first course contract

- Remove remaining assumptions that courses must ship a bespoke `setup.sh` flow.
- Keep the course installer as the single place that applies `packages.txt`, `links.txt`, and `env.txt`.
- Make sure course maintainers have one clear migration path from Dockerfile-based setup to CCC manifests.

### 4. Polish professor/student-facing UX

- Improve error messages so installer failures always point at the relevant log file.
- Make the docs describe the current workflow, not the old host/container split.
- Make the default vs course-specific distinction easy to understand from the docs and registry.
- Keep the command surface small and predictable: `init`, `open`, `cleanup`, `config`, `list`.

### 5. Validate with more course migrations

- Add at least one more course that is apt/package-heavy.
- Add at least one course that depends on a more custom course image.
- Use those conversions to decide whether CCC can support them as default-container courses or whether they need to remain course-specific.

### 6. Decide what belongs in the release-ready toolset

- Leave packaging work for later unless a distribution target is required immediately.
- Keep compatibility wrappers only where they help transition from old flows to the new one.
- Remove any stale docs or tests that still describe the old `setup.sh`-first behavior.
