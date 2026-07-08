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
| ccc.sh                | Entry point; dispatches to the CLI wrapper and helper scripts in `share/`    |
| share/utils.sh        | Logging, mode detection, config, and versioning utilities                   |
| share/courses.sh      | Courses and registry management utilities                                   |
| share/container_helpers.sh | Container setup utilities                                                |
| share/host_mode.sh    | (removed) Host dispatcher was consolidated into `ccc.sh` and helper libs   |
| share/container_mode.sh | (removed) Container dispatcher was consolidated into `ccc.sh` and helper libs |
| Dockerfile.template   | Image definition                                                            |
| registry.csv          | Course registry                                                             |
