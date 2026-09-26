# impression-studio-framework
The framework layer for the Impression Studio project

Impression Studio is a PS2 development framework built on top of [Tyra](https://github.com/h4570/tyra), a PS2 game engine by Sandro Sobczyński.
It is an independent project and is not affiliated with the Tyra author.

## Getting started

    git clone --recursive https://github.com/<your-user>/impression-studio-framework.git

## Building and running

Prerequisites: Git and Docker. Everything that compiles runs inside a toolchain
container, so nothing else is installed on your machine.

Copy `impression.local.conf.example` to `impression.local.conf` and set
`PCSX2_PATH` (the file is ignored by git). Then, from the repository root:

    scripts/build-project.sh          # builds Tyra, the framework, then the project
    scripts/run-project.sh            # runs the project's ELF in PCSX2 on the host

On Windows use the `.cmd` shims, which run the PowerShell scripts with the
execution policy bypassed for that one call (no system settings change):

    scripts\build-project
    scripts\run-project

`run-project --build` (`-Build` in PowerShell) builds and runs in one step; the
other options are `--restart`, `--wait` and `--dry-run`.

**VS Code.** `.vscode/tasks.json` has build, run, clean, engine and container tasks
(`Ctrl+Shift+B` builds). **F5** runs the "Impression: build and run" configuration,
which builds the project and launches it in PCSX2 (it is a terminal launch, not a
debugger). A second configuration asks for the project folder. The workspace
terminal on Windows starts PowerShell with the execution policy bypassed, so
`.\scripts\imp.ps1` also works when typed by hand.

**First run.** The scripts build two Docker images automatically. The first is the
PS2DEV toolchain, compiled from source at a fixed 2022 snapshot (see
`docker/Dockerfile.ps2dev` for why); it takes a long while once and is then cached
by Docker. Tyra and the framework are also compiled on first use, and only
recompiled when they change.

**Which project.** Any folder with a `Makefile` works; it is mounted into the
container at `/project`. Choose it with `PROJECT_DIR` in `impression.local.conf`
(default `examples/hello`), or pass a folder: `scripts/build-project.sh ~/games/mine`.
A project's Makefile is two lines, see `examples/hello/Makefile`:

    TARGET := game.elf
    include $(IMPRESSION_HOME)/mk/project.mk

**The container.** It stays running between commands and is started (or recreated
when the project changes) automatically. Manage it with `scripts/imp.sh`
(`scripts\imp` on Windows): `start`, `stop`, `restart`, `status`, `shell`, and the
engine commands `build-engine`, `clean-engine`, `build-framework`,
`clean-framework`, plus `make [args]` for raw make in the project. Run
`scripts/imp.sh --help`.

These scripts are also the interface the future GUI editor uses; exit codes and
output lines are specified in [docs/tooling-contract.md](docs/tooling-contract.md).

## Logging

`inc/impression/log.hpp` provides `IMP_LOG(Category, Level, "format", args...)`
with per-category levels (compile-time floor plus runtime `Log::setLevel`).
Output goes live to PCSX2's EE console (enable `EnableEEConsole` in PCSX2's
`[Logging]` settings) and to `<project>/bin/log.txt`. Tyra's own `TYRA_LOG`
lines are captured too. See `examples/hello` and
[docs/tooling-contract.md](docs/tooling-contract.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
