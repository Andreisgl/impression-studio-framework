# impression-studio-framework
The framework layer for the Impression Studio project

Impression Studio is a PS2 development framework built on top of [Tyra](https://github.com/h4570/tyra), a PS2 game engine by Sandro Sobczyński.
It is an independent project and is not affiliated with the Tyra author.

## Getting started

    git clone --recursive https://github.com/<your-user>/impression-studio-framework.git

## Building

Prerequisites: Git and Docker (with the `docker compose` plugin).

Build Tyra's engine library once per clone. Rebuild only after the Tyra submodule
changes; `make` only recompiles what changed.

Linux / macOS:

    scripts/build-tyra.sh

Windows (PowerShell):

    scripts\build-tyra.ps1

Add `--clean` (or `-Clean` on Windows) to rebuild from scratch. The result is
`extern/tyra/engine/bin/libtyra.a`. The toolchain image is pinned in
`docker-compose.yml`.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
