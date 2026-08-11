## How the project works

CCC (Common Course Containers) gives students standardized Linux environments per course using Podman. A single `ccc` binary runs in two modes — on the host (macOS) and inside the container — distinguished by the presence of /etc/ccc-container.

## The Flow

```
Student's laptop (host mode)                         Container (container mode)
────────────────────────────                         ──────────────────────────
ccc init         creates courses/ dir,
                 saves path to ~/.config/ccc/config

ccc setup foo    builds image
                 starts ephemeral container          ccc setup foo
                                                     git clone <repo>
                                                     bash setup.sh

ccc run foo      starts persistent container
                 mounts courses/ at /courses
```

## File layout

| File                  | Role                                                                        |
| --------------------- | --------------------------------------------------------------------------- |
| bin/ccc               | Entry point; dispatches to the CLI wrapper and helper scripts in `share/`    |
| share/utils.sh        | Logging, mode detection, config, and versioning utilities                   |
| share/config.sh       | Configuration read/write and defaults                                      |
| share/registry.sh     | Registry parsing and lookup utilities                                       |
| share/courses.sh      | Courses management and registry queries (course naming, image modes, etc.)   |
| share/container_helpers.sh | Podman/Docker primitives (build, network, run, inspect)                |
| share/open.sh         | Course environment orchestration (ccc open implementation)                 |
| share/cleanup.sh      | Course cleanup and state removal (ccc cleanup implementation)              |
| share/status.sh       | Status inspection and reporting (ccc status implementation)                |
| share/session.sh      | Session and environment tracking utilities                                  |
| Dockerfile.template   | Image definition                                                            |
| registry.csv          | Course registry                                                             |
