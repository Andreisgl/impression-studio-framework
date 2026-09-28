# Impression Studio SDK

This folder is a starting point for a PS2 game built on
[Impression Studio](https://github.com/Andreisgl/impression-studio-framework), a
framework built on top of [Tyra](https://github.com/h4570/tyra). Copy its contents
into your own game repository — that's the whole setup. The framework and Tyra are
already built into the Docker image; you never need to check out or build either
yourself.

## Prerequisites

Git and Docker. Nothing else is installed on your machine; the compiler and every
other tool run inside the container.

## Building and running

    ./imp.sh build          # builds this project
    ./imp.sh run            # runs the ELF in PCSX2 on your host

On Windows, use the `.cmd` shim instead (it runs the PowerShell script with the
execution policy bypassed for that one call; no system settings change):

    imp build
    imp run

The first `build` pulls the SDK image (about a gigabyte, once; Docker caches it
after that). `imp.sh run --build` (`-Build` in PowerShell) builds and runs in one
step. Other `run` options: `--restart`, `--wait`, `--dry-run` (`-Restart`, `-Wait`,
`-DryRun`).

Before `run` works, set `PCSX2_PATH` in `impression.local.conf`, which is created
automatically (from `impression.local.conf.example`) the first time you build or
run. It's gitignored: this setting is per machine.

## Your game

`Makefile` names the ELF (`TARGET`). Sources go in `inc/` and `src/`; this template
ships a tiny working sample (`hello_game.hpp/.cpp`, `main.cpp`) so the above
commands work out of the box — replace it with your own game.

## Logging

Games log through `<impression/log.hpp>` (`IMP_LOG(Category, Level, "format", ...)`):
output goes live to PCSX2's EE console (enable `EnableEEConsole` under PCSX2's
`[Logging]` settings) and to `bin/log.txt`, which `imp run` clears before each launch.

## Other commands

    imp clean     # removes this project's build output
    imp shell     # opens a shell in the toolchain container
    imp pull      # re-pulls the SDK image (e.g. after an update)
    imp status    # shows whether the container is running

## Pinning a version

By default `imp` uses `andreisgl/impression-studio-sdk:latest`. To pin an exact
version, set the `IMPRESSION_SDK_IMAGE` environment variable, e.g.
`IMPRESSION_SDK_IMAGE=andreisgl/impression-studio-sdk:<tag>`.

## License

Impression Studio and Tyra are Apache License 2.0. Your own game code under `inc/`
and `src/` is yours; nothing here requires a particular license for it.
