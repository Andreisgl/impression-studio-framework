# impression-studio-framework
The framework layer for the Impression Studio project

Impression Studio is a PS2 development framework built on top of [Tyra](https://github.com/h4570/tyra), a PS2 game engine by Sandro Sobczyński.
It is an independent project and is not affiliated with the Tyra author.

## Getting started

    git clone --recursive https://github.com/<your-user>/impression-studio-framework.git

## Building and running

Prerequisites: Git and Docker. Everything that compiles runs inside a toolchain
container, so nothing else is installed on your machine.

`<project>/impression.local.conf` is created automatically the first time a
launcher touches that project (from `impression.local.conf.example`; the file
itself is ignored by git). Open it and set `PCSX2_PATH` before running a project.
Then, from the repository root:

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

**First run.** The scripts build the toolchain image automatically: the official
PS2DEV image (pulled once, about 1 GB, pinned by digest) plus `vclpp`, which takes a
minute or two and is then cached by Docker. Tyra and the framework are also compiled
on first use, and only recompiled when they change.

**Toolchain and the Tyra checkout.** The default toolchain (GCC 15, current ps2sdk,
`openvcl`) builds the ported Tyra fork, the branch `port/ps2dev-2.0` of the fork that
`extern/tyra` should have checked out. It cannot build upstream `h4570/tyra`, which
needs `bin2s` and Sony's `vcl`. For that (or to reproduce the old environment) set
`IMPRESSION_TOOLCHAIN=snapshot`: it selects the July 2022 PS2DEV, compiled from source
(`docker/Dockerfile.ps2dev`, tens of minutes once) and has its own container. Any other
value is an error. Details and status of the port: `docs/tyra-port-notes.md`.

**Which project.** The default is `project/` at the repository root (seeded as a
copy of `examples/hello`; replace its sources with whatever you are developing).
Any other folder with a `Makefile` also works, mounted into the container at
`/project`: set the `PROJECT_DIR` environment variable, or pass a folder,
e.g. `scripts/build-project.sh ~/games/mine`. A project's Makefile is two lines,
see `project/Makefile`:

    TARGET := game.elf
    include $(IMPRESSION_HOME)/mk/project.mk

**The container.** It stays running between commands and is started (or recreated
when the project changes) automatically. Manage it with `scripts/imp.sh`
(`scripts\imp` on Windows): `start`, `stop`, `restart`, `status`, `shell`, and the
engine commands `build-engine`, `clean-engine`, `build-framework`,
`clean-framework`, plus `make [args]` for raw make in the project. Run
`scripts/imp.sh --help`.

**IntelliSense.** Run `scripts/imp.sh sync-ide` (`scripts\imp.cmd sync-ide` on
Windows, or the VS Code task "Impression: sync IDE (IntelliSense)") once per
project, and again after a toolchain or Tyra update. It copies the exact
Tyra/framework/toolchain headers this project builds against into
`<project>/.impression/include/` and generates `<project>/.vscode/c_cpp_properties.json`
to match — no manual download, and no host paths to hand-edit.

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
