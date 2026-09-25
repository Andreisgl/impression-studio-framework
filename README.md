# impression-studio-framework
The framework layer for the Impression Studio project

Impression Studio is a PS2 development framework built on top of [Tyra](https://github.com/h4570/tyra), a PS2 game engine by Sandro Sobczyński.
It is an independent project and is not affiliated with the Tyra author.

## Getting started

    git clone --recursive https://github.com/<your-user>/impression-studio-framework.git

## Building

Prerequisites: Git and Docker (with the `docker compose` plugin).

One command builds everything. It runs `make` inside the pinned toolchain
container, builds Tyra's engine library first (a no-op when it is already up to
date), then the framework:

Linux / macOS:

    scripts/make.sh

Windows (PowerShell):

    powershell -ExecutionPolicy Bypass -File .\scripts\make.ps1

Windows disables running PowerShell scripts by default, so the command above
bypasses that policy for this one run without changing any setting. Run it from
an open terminal (not by double-clicking) so errors stay visible. To allow local
scripts permanently for your user, run
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` and then `.\scripts\make.ps1`.

Outputs: `extern/tyra/engine/bin/libtyra.a` and `bin/libimpression.a`. Games
link both. Arguments are passed to make: `scripts/make.sh tyra` builds only
Tyra's library, `scripts/make.sh clean` cleans the framework's objects, and
`scripts/make.sh clean-tyra` cleans Tyra's.

The toolchain image is pinned in `docker-compose.yml`.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
