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

Windows commands are run as
`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\<name>.ps1 ...`,
Linux/macOS commands as `scripts/<name>.sh ...`. Paths are relative to the
repository root or absolute; a project must be a subdirectory of this repository
that has a `Makefile` (for example `examples/hello`).

| Purpose | Windows | Linux / macOS |
|---|---|---|
| Build a project completely (Tyra, framework, project) | `build-project.ps1 <project>` | `build-project.sh <project>` |
| Run a project's ELF in PCSX2 | `run-project.ps1 <project> [-Build] [-Restart] [-Wait] [-DryRun]` | `run-project.sh <project> [--build] [--restart] [--wait] [--dry-run]` |
| Raw make in the toolchain container | `make.ps1 [make args]` | `make.sh [make args]` |

## Exit codes

| Code | Meaning | Typical GUI reaction |
|---|---|---|
| 0 | Success | continue |
| 1 | The build or launch itself failed | show the build log |
| 2 | Usage error: bad or missing project, no `.elf` found, more than one `.elf` | fix the request |
| 3 | Environment problem: Docker or git missing, `PCSX2_PATH` unset or wrong | open the settings dialog |

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

Machine-specific settings live in `impression.local.conf` at the repository root
(ignored by git; start from `impression.local.conf.example`). It is plain
`KEY=value` lines and is parsed, never executed, so a GUI can read and write it
safely.

| Key | Meaning |
|---|---|
| `PCSX2_PATH` | PCSX2 executable, or the folder containing it (required to run) |
| `PCSX2_ARGS` | optional extra flags passed before the ELF, split on whitespace |

An environment variable with the same name overrides the file for that one
invocation. A GUI that keeps its own settings can therefore skip the file and set
`PCSX2_PATH` in the child process environment.

## Notes

- PCSX2 launch flags: Qt builds (2.x) use `-elf <file>`; old wx builds use
  `--elf=<file>`. The scripts pick by executable name and the presence of
  `qt.conf`, as TyraX does. Confirm any extra flags (such as `-batch`) against
  your PCSX2 version and put them in `PCSX2_ARGS`.
- Long-running commands: `build-project` can take minutes on the first run. A GUI
  should run it asynchronously and stream stdout to a log pane.
- Projects outside this repository are not supported yet; the container mounts
  only the repository root.
