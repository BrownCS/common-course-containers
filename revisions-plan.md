### Installation and Location

Currently, CCC is downloaded via a git-clone of the remote repository and then installed using ./install.sh and ccc init. In ccc init, the course directory is set to be within the CCC repository clone. I want to change installation and ccc and courses dir locations to be separate.

First, CCC will not be installed via a git clone. Instead, it will be installed using a package because the installer can (1) run install/init scripts so that the user doesn't have to and (2) this practice aligns with professional tools.

The installation process will ask the user where they want the CCC tool stored. They can choose a location or use the default. The default path will be something like /home/user/ccc-dir (copy or git clone of the repo). 

The installation process will also prompt users about where the /courses directory lives. It will NO longer live in the CCC directory by default. The default location will be home/user/courses, unless the user specifies otherwise. The CCC tool is callable through its functions, and effects courses that are stored elsewhere. That is, if we remove CCC, we shouldn't remove the courses directory, which is why they're separate.

The install process will also set any necessary variables and ensure dependencies are installed. Question: Do any of these have to be chosen by the user? Or is the courses directory the only important one? We also might not need to check for direnv anymore, see later.

Note on implementation order: during development it's advisable to implement the "git-install" (developer/bootstrap) workflow first — the user clones the repo and runs `./install.sh` or `ccc init`. This lets us iterate quickly on behavior and auto-update semantics. Packaging (deb/rpm/homebrew) should be implemented later once core features are stable.


### Running a course environemtn with CCC

Currently, to run a course environment with CCC, we can do ccc setup [course] or ccc run [course]. These two commands do very similar things and could be merged into one, and also require a container. CCC no longer stands for Common Course Container, but instead Common Course Configuration. It will support courses that do and do not need a container.

The command will now be a singular `ccc open [course]`. It will work as follows:

1. Check if [course] is in registry. If not, error. 
2. Check course to see if they need a container (and if that container is either a specific container or one of CCC’s shared containers). This could either be a field in the registry.csv file (probably the best choice) or in a course development file. The course development file requires viewing/pulling/cloning the remote course dev repo, which we do later, though. Regardless, we set some environment variables here.
3. Check the remote version of the ccc repo. If the remote version is ahead of the local version, prompt user to update. If they consent, do a git pull and re-run init script. 
4. Ensure there is a subdirectory in the courses directory for the course. If there isn't one, prompt user to make one or choose default (which would just be courses/course)
5. If the course is being opened for the first time, then git clone [course] dev repo. If the course is not being opened for the first time, check the version of the remote repo. If it is ahead of the local version, prompt user to update. If they consent, do a git pull. 
6. If container is needed (variable set in step 1) make/run appropriate container and enter it.
7. Regardless of whether in a container or not, launch a new shell in the courses directory with the course dependencies and packages installed. 
8. Now the user should be in a shell with the course environment set up. Print some message. Ex: “Now in [course] environment, ready to work! Clone course assignment repos”


### Closing or Swiching courses

Currently, to close a course or run a new course, you have to `exit` the container and re-run the setup process. With the new ccc open logic, this changes.

To exit or close a course, students can run `ccc close`. This will do the following:

1. Close the shell opened for this course
2. Once returned to the previous process, if in a container, leave it.
3. Should be in the location/directory where the initial `ccc open` command was run.

This works similarly for courses that use containers and don't use containers -- the course shell closes, and if there's a container, that closes too. 

Switching between courses will be similar. If a user tries to run `ccc open [course]` while working on another course, it should essentially run a `ccc close` then a new `ccc open`, but before running `ccc close` prompt user with 'in order to open a new course, we must close the current one. Is that ok?'


### Cleanup, Advanced Commands

The cleanup commands remain similar to what they currently are, but need to be reworked. Currently we support removing container, image, network or the entire CCC tool. We will do the same here, but the unstalling CCC must also remove all containers/images/networks. This isn't fully the case already -- if you run ./uninstall and then try to reinstall ccc, none of the other commands will work because podman has old/stale containers that haven't been removed yet.

Archival is also something we want to support, but is not a huge priority. If a student already has old semester repo cloned adn wants to run that old version of the course, they can probably run on current CCC container. CCC just needs to use the local code, not pull from the remote repo first to update. We could also have courses maintain archived development repositories, and then support some `ccc open [course] -archive [semester]

We will maintain these advanced commands for users who care:

1. `ccc config` allows users to reset courses directory path (and potentially copy over files from previous location). Similar to how this works now
2. `ccc uninstall` does a full removal of all containers, files, and environment variables created/set by CCC
3. `ccc remove [target]` removes container, image, network (used by uninstall)
4. `ccc int`, `ccc setup`, `ccc update`, `ccc upgrade,` and other previous commands will all be available to the user, but shouldn’t really be necessary to use
5. `ccc list -flag [avail or installed]' --> avail flag will print all available courses in the registry, installed flag will print all courses install on local machine.
6. potentially an archive flag for ccc open


### Default Architecture and use of direnv/lmod

Container images are built for os/cpu platforms like linux/amd64 or linux/arm64. Ideally, both the OS and architecture match the machine/kernel running the container. If the OSs mismatch (like a Mac running linux), the container needs to run a lightweight VM with a appropriate kernel for the container OS. If the architecture mismatches, then it needs to be emulated by something like QEMU, which slows things down. Having to do BOTH of these (emulation/machine code translation and VM for proper kernel) is possible, but probably unnecessary.

We should (and this is currently the case) default to using the underlying architecture of the machine running the container. For courses that need a specific architecture, that will have to be tweaked in their dockerfile (will have to be a different container than the shared container)

We currently use direnv to help maintain PATH and other environment variables when switching directories. We had thought about switching to lmod, but then realized if we implement opening a course as opening a new shell with the proper environment, we actually don't need direnv or lmod. Is this correct? if so, we can forgo using either at all.


### Important note on host mode vs container mode

This tool is no longer something that always starts a container. A container could be necessary for a course, but it might not be. You could just set up a course development by installing certain versions of packages. That's why `ccc open` doesn't have two "tracks" or "branches" so to speak. The container does the same thing the non-container version does -- starts a new shell for the course. So, I want to move away from the host mode vs container mode separation. We can preserve the workings of the code, but restructure the files and flow to remove this.

--- Copilot's writing below ---

## Notes, decisions, and answers to your questions

Below are short answers to the four notes you raised plus a few decisions I recommend so we can move to implementation.

1) Installer linking to GitHub and automatic updates

- It's possible for the installer to link to a GitHub release or to a git repository. However, automatic updates performed on `ccc open` are risky when `ccc` is installed by a package manager (deb/rpm/homebrew) because the package manager should own updates. Recommended approach:
	- Support two install modes: "git-installed" (developer or bootstrap install) and "packaged" (installed via OS package manager).
	- When git-installed, `ccc open` may optionally auto-check the remote repo and offer to update (or auto-update with an explicit opt-in). If an update occurs, re-run init and re-exec the new `ccc` process.
	- When packaged, `ccc open` should only *check* for a newer version and print an instruction (or link) telling the user how to update via their package manager.

2) Why not just use `registry.csv`?

- You can use `registry.csv` as the single source of truth. It's simple and portable. The only limitation: CSV is less flexible for optional structured fields (lists, nested objects). Practical compromise:
	- Keep `registry.csv` as required, but add well-defined optional columns for: `repo_url`, `requires_container` (true/false), `container_image`, `container_arch`, `default_branch`, and `notes`.
	- Support an optional `registry/` directory containing one-file-per-course metadata (yaml/json) for courses that need richer metadata. The code will prefer `registry/<id>.(yml|json)` if present, otherwise fall back to `registry.csv`.

3) Flags for `ccc open`

- I agree: `ccc open` should be able to decide whether a container is necessary by reading the registry metadata. Keep the default surface minimal. For now implement no extra flags other than an `--archive` option planned later. We will, however, implement non-interactive flags for scripting (like `--yes` or `--force`) so automation is possible.

4) Restructuring to remove host vs container mode

- I also agree. We should refactor the scripts so common behaviors (config loading, registry parsing, session tracking, launching a shell) are implemented in reusable library scripts, and both container and host workflows call into those libraries. The repo layout should be clarified (see plan below).

## Cross-platform config storage decision

- Don't hard-rely on XDG. Use a small resolution strategy:
	- If `XDG_CONFIG_HOME` is set, use `$XDG_CONFIG_HOME/ccc` (Linux, other Unix that set it).
	- Else if on macOS (detectable via `uname` and platform heuristics), use `~/Library/Application Support/ccc`.
	- Else if on Windows (detect via environment), use `%APPDATA%\ccc`.
	- Else fall back to `~/.ccc` or `~/.config/ccc` as a final fallback.

This keeps things cross-platform while still encouraging canonical locations on Linux.

- User consent for auto-updates: do not enable auto-updates by default. The installer or first-run `ccc init` should prompt the user whether they want `ccc` to auto-check and optionally auto-apply updates on `ccc open`. Record the response in the config as `CCC_AUTO_UPDATE` (default: `false`).

## Chronological implementation plan (milestones)

The plan below is ordered so each milestone is small, testable, and builds on the previous work.

Milestone 0 — Project hygiene (small, fast)
- Add CONTRIBUTORS.md and CODE_OF_CONDUCT.md (optional).
- Add a short developer README section describing the code layout we will adopt.

Milestone 1 — Config and registry basics (safe, foundational)
- Add `lib/config.sh` that implements cross-platform config lookup and read/write helpers.
- Decide and document config keys: `CCC_INSTALL_DIR`, `CCC_COURSES_DIR`, `CCC_INSTALL_MODE` (`git`|`package`).
- Extend `registry.csv` with the recommended optional columns. Add a short header comment showing column names.
- Add `lib/registry.sh` parser that reads `registry.csv` and optional `registry/<id>.yml`.

Milestone 2 — CLI dispatcher and basic commands
- Add `bin/ccc` (POSIX shell) CLI that sources `lib/config.sh` and `lib/registry.sh` and dispatches commands.
- Implement `ccc config` (get/set), `ccc list --avail`, `ccc list --installed`.
- Make `install.sh` write initial config if missing (interactive prompts with sane defaults).

Milestone 3 — `ccc open` (host-only flow, prototyping)
- Implement `lib/open.sh` host flow: ensure course directory exists, clone if missing, run course's `setup.sh` or configured setup, then `exec` an interactive login shell in that directory with environment variables applied.
- Implement session tracking (write `session.json` to config dir with course id, pid, container id if any).
- Add basic tests that `ccc open` for a fake local registry entry creates the directory and launches a subshell (test with a wrapper).

Milestone 4 — Container integration and labels
- Implement `lib/container.sh` that uses Docker/Podman to run containers and applies deterministic labels (e.g., `io.ccc.course=<id>`, `io.ccc.managed=true`) so cleanup is safe.
- Integrate container flow into `ccc open`: if `requires_container` is true, run or reuse a labeled container, mount `CCC_COURSES_DIR`, and `exec` a shell inside container.
 - Default behavior: containers are ephemeral. `ccc open` will create a container for the session and `ccc close` will remove it, unless the user explicitly enables reuse in config (`CCC_CONTAINER_REUSE=true`). This keeps open/close semantics simple and predictable.

Milestone 5 — `ccc close`, `ccc remove`, `ccc uninstall`
- Implement `ccc close` to terminate session and optionally stop/remove container if not reused.
- Implement `ccc remove` to remove images/containers/networks that are labeled and match targets.
- Implement `ccc uninstall` to remove CCC-managed artifacts and optionally preserve `CCC_COURSES_DIR`.

Milestone 6 — Update checks, safety, and UX polish
- Implement update-check behavior with clear policy:

- For `git` installs: ask the user during initial setup whether they want automatic updates on `ccc open`. Default is `false`. If the user opts in, `ccc open` will perform a safe remote check and update flow (fetch, verify, apply or rollback) before launching the session. If a session is active, defer updates until close unless `--force-update` is explicitly given.
- For `packaged` installs: never auto-apply updates; only show clear instructions to update via the package manager. Optionally offer a helper command that delegates to the package manager when user consents.
- Add prompts, `--yes`, `--force` flags for scripting. Add clear help text and manpage.

Milestone 7 — Backward compatibility and cleanup
- Keep legacy `setup.sh` wrapper for compatibility but mark as deprecated.
- Reorganize existing `lib/*.sh` into the new `lib/` layout, removing duplicate host/container code.

Milestone 8 — Optional features and follow-ups
- Add `--archive` support and implement per-course archive entries in the registry.
- Add small automated tests (bats or sh) for fast CI checks.
- Add a small README section describing how to package CCC for apt/rpm/homebrew.

Milestone 9 — Packaging (deferred)
- Create packaging recipes for target platforms (deb, rpm, Homebrew formula).
- Implement package post-install hooks that run the same init logic as `ccc init` (prompt for `CCC_COURSES_DIR`, ask auto-update opt-in, create config files) without requiring the user to run manual steps.
- Document packaging instructions and CI steps to build the packages. This milestone is explicitly deferred until core functionality (Milestones 1–7) is stable.

Each milestone should be one or more code commits and include 1–2 tests. I can start with Milestone 1 now (config + registry parser). If you want that, say "Start milestone 1" and I'll add `lib/config.sh`, extend `registry.csv` with column docs, and create `lib/registry.sh` with unit tests.

---

If you'd like edits instead of an append or want the plan expanded into an actionable task list for sprints, tell me which milestone to start and I'll implement it.


