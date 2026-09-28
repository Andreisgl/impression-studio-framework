<!--
Copyright 2026 Andrei Segal
SPDX-License-Identifier: Apache-2.0
-->

# Tooling contract

How the future GUI editor (or any other tool) drives builds and runs. It never
needs to know about Docker, make, or PCSX2 flags: it spawns one of the scripts
below as a child process and reads its exit code and output. Treat everything on
this page as a stable interface; change it deliberately.

## Commands

Windows commands are run as `scripts\<name>.cmd ...` (a shim that starts
`<name>.ps1` with the execution policy bypassed for that one process), Linux and
macOS commands as `scripts/<name>.sh ...`. All of them build and run the project in
a long-lived toolchain container that they start (or recreate) when needed.

**Choosing the project.** An optional folder argument, else the `PROJECT_DIR`
environment variable, else `project/` at the repository root (seeded as a copy of
`examples/hello`). A folder argument is relative to the current directory and
`PROJECT_DIR` to the repository root; absolute paths work, and any folder on the
host works, inside or outside this repository. The folder must contain a `Makefile`
(exit 2 otherwise): it is used exactly as given, nothing is searched for. Inside the
container the project is always `/project`. Changing the project recreates the
container (a few seconds) in the `modern`/`snapshot` flavours; the `sdk` flavour
gives each project its own container instead (see below).

**Toolchain flavour** (`IMPRESSION_TOOLCHAIN` environment variable):

| Value | Image | Contains | Container |
|---|---|---|---|
| `modern` (default) | `impression/toolchain:modern` | the official `ps2dev/ps2dev` image plus `vclpp`; builds the ported Tyra fork | `impression-dev` |
| `snapshot` | `impression/toolchain:dev` | a from-source July 2022 PS2DEV build; builds unported upstream Tyra | `impression-dev-snapshot` |
| `sdk` | `impression/sdk:local` | the framework and Tyra prebuilt (baked in at image build time, `IMPRESSION_HOME=/impression`); no framework checkout is mounted | `impression-sdk-<hash>`, one per project (a short hash of the resolved project path) |

Any other value is a usage error (exit 2). `sdk` is for local testing of the SDK
experience against an arbitrary project folder from within this repo; it is not yet
what a real SDK end user (no checkout of this repo) would use — see the TODO.

| Purpose | Command |
|---|---|
| Build a project completely (Tyra, framework, project) | `build-project [project]` |
| Run a project's ELF in PCSX2 on the host | `run-project [project] [--build] [--restart] [--wait] [--dry-run]` (PowerShell: `-Build -Restart -Wait -DryRun`) |
| Raw make in the project folder | `make [make args]` |
| Container and engine management | `imp [-p project] start\|stop\|restart\|status\|shell\|rebuild-image\|build\|clean\|build-engine\|clean-engine\|build-framework\|clean-framework\|sync-ide` |

## Exit codes

| Code | Meaning | Typical GUI reaction |
|---|---|---|
| 0 | Success | continue |
| 1 | The build or launch itself failed | show the build log |
| 2 | Usage error: bad or missing project, no `.elf` found, more than one `.elf` | fix the request |
| 3 | Environment problem: Docker missing or not running, git or the Tyra submodule missing, an image failed to build, `PCSX2_PATH` unset or wrong | open the settings dialog |

## Output

- **stdout** carries the tool's log (make output, streamed live) and, on success,
  `KEY=value` lines. A tool should parse lines that start with `IMPRESSION_` and
  treat all other lines as log text to display.
- **stderr** carries error messages, always prefixed with `error: `.

| Line | Emitted by | Meaning |
|---|---|---|
| `IMPRESSION_ELF=<absolute path>` | `build-project` | the built ELF (last line on success) |
| `IMPRESSION_PID=<pid>` | `run-project` (detached) | process id of the emulator; use it to stop or track it |
| `IMPRESSION_CMD=<command>` | `run-project --dry-run` | the command that would run; nothing is launched |

## run-project behaviour

- Without `--build` it runs the ELF that already exists in `<project>/bin`.
  It exits 2 if there is not exactly one `.elf` there.
- Default is **detached**: it launches PCSX2, prints `IMPRESSION_PID`, and
  returns. `--wait` stays in the foreground until the emulator exits; the
  emulator's own exit status is not reported (always 0 once it started).
- `--restart` stops a running instance of the same emulator executable before
  launching. It is opt-in because it also closes emulator windows you opened
  yourself.
- Build first and run in one step with `--build` (equivalent to running
  `build-project` and then `run-project`).

## Game log

Games use the Impression logging layer (`inc/impression/log.hpp`, see
`examples/hello`): call `Impression::Log::init()` before creating the Tyra
`Engine`, then log with `IMP_LOG(Category, Level, "printf format", args...)`.

**Line format** (stable; parse this):

    [Category][Level] message

`Level` is one of `Verbose`, `Debug`, `Info`, `Warning`, `Error`. Lines without
a bracket prefix come from raw stdout, mainly Tyra's own `TYRA_LOG` output
(`LOG: ...`) and its startup banner; show them as generic engine output.

**Two sinks, both on by default** (`LogConfig`):

| Sink | Where | Timing |
|---|---|---|
| Serial | PCSX2's console / `emulog.txt` (needs `EnableEEConsole = true` in PCSX2) | live, per line |
| File | `<project>/bin/log.txt` | buffered, flushed by `Log::flush()` (call it every frame; free when idle) and immediately on every `Error` |

`run-project` deletes the previous `log.txt` before each launch, so a GUI can
tail the file for a log pane. With `hookStdout` (default) libc's stdout is
redirected into the same sinks, so `printf` and `TYRA_LOG` show up too; keep
Tyra's own `EngineOptions::writeLogsToFile` off in that case.

**Filtering.** Levels below `IMP_LOG_MIN_LEVEL` are compiled out (default: all
in debug builds, Warning and above with `NDEBUG`); their arguments are not
evaluated. The rest are filtered per category at runtime:
`Impression::Log::setLevel("Player", LogLevel::Verbose)` or
`Impression::Log::applySpec("Player=Warning,Physics=Verbose")`.

**Limits.** Not thread-safe (log from the main thread). Messages longer than 512
bytes are truncated. On real hardware, serial output is slow (38400 baud) and
the `host:` log file does not exist; disable sinks through `LogConfig`.

## Configuration

Machine-specific settings for a project live in `<project>/impression.local.conf`
(ignored by git) — next to that project's `Makefile`, not at the repository root.
It is created automatically, from `impression.local.conf.example`, the first time a
launcher touches that project (a one-line note is printed to stderr); nothing needs
to be copied by hand. It is plain `KEY=value` lines and is parsed, never executed,
so a GUI can read and write it safely. This location is deliberate: PCSX2 runs on
the host, so its settings have to be host-side, and keeping them with the project
(rather than with the toolchain) means the same file convention works whether the
project is this repository's own `project/`, a folder elsewhere on disk, or —
once built — a project in a future SDK flavour that has no toolchain checkout to
copy the example from.

| Key | Meaning |
|---|---|
| `PCSX2_PATH` | PCSX2 executable, or the folder containing it (required to run) |
| `PCSX2_ARGS` | optional extra flags passed before the ELF, split on whitespace |

An environment variable with the same name overrides the file for that one
invocation. A GUI that keeps its own settings can therefore skip the file and set
`PCSX2_PATH` in the child process environment.

`PROJECT_DIR` selects which project the launchers use when no folder argument is
given (default `project/`). It is a real environment variable, never a config-file
entry: since the config file lives inside a project, it cannot also be what picks
the project.

## Notes

- PCSX2 launch flags: Qt builds (2.x) use `-elf <file>`; old wx builds use
  `--elf=<file>`. The scripts pick by executable name and the presence of
  `qt.conf`, as TyraX does. Confirm any extra flags (such as `-batch`) against
  your PCSX2 version and put them in `PCSX2_ARGS`.
- Long-running commands: the very first `build-project` pulls and builds the toolchain
  image (a few minutes, output goes to the terminal; the optional `snapshot` toolchain
  takes tens of minutes) and compiles Tyra and the framework; later runs recompile
  only what changed. A GUI should run it asynchronously and
  stream stdout to a log pane.
- `IMPRESSION_ELF` is always an absolute host path; the container's own
  project-relative path is translated by the launcher.
- A folder outside this repository works as a project (it is mounted at `/project`).
