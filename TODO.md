# TODO

## Tooling
- [x] **Projects outside this repo** (dev flavor). Any folder with a `Makefile` works: the launcher mounts it at `/project` in the long-lived toolchain container (`PROJECT_DIR` in `impression.local.conf`, or a folder argument). The SDK flavor (framework and Tyra baked into an image for people who only have a game repo) is still open, see below.
- [ ] **SDK flavor.** `docker/Dockerfile.sdk`: `FROM` the toolchain image, copy the framework repo (with `extern/tyra`) to `/impression`, seed a per-commit named volume mounted over it so Tyra and the framework build on first use and persist, one long-lived container per project (`impression-sdk-<hash>`), `IMPRESSION_HOME=/impression`, per-user config for the PCSX2 path. Publishing a ready-made image is a later option.
- [ ] **IDE support for SDK users** (`imp sync-ide`): copy Tyra, framework, ps2sdk and newlib headers to `<project>/.impression/include/` and write `c_cpp_properties.json` and `compile_commands.json`, so IntelliSense resolves `<tyra>` and `<impression/log.hpp>`. Optional: VS Code Dev Containers "Attach to Running Container".
- [x] **VS Code F5 = build and run.** `.vscode/tasks.json`, `launch.json` (`node-terminal` configs, plus a project-folder prompt) and a workspace terminal profile with the execution-policy bypass. Written and the JSON validated, but not yet exercised from the VS Code UI: try F5 once and fix anything that looks off.
- [ ] **Toolchain snapshot.** The image is the July 2022 PS2DEV (GCC 11.3, ps2sdk with `bin2s`), because current ps2dev has no `bin2s` and ships GCC 15, and Tyra's Makefile.base needs both. Long term, port the Tyra fork to current ps2dev (replace `bin2s` in `Makefile.base`, make `vcl` run on musl or drop it, fix GCC 15 warnings) and drop the snapshot.
- [x] **Real-time program output.** Done with the IMP_LOG layer (`inc/impression/log.hpp`, `src/log*.cpp`). Root cause of the lost output: on this toolchain and PCSX2 2.6.3 libc's `printf` never reaches PCSX2's console (a pure ps2sdk ELF behaves the same, so Tyra's IOP reset is not the cause), while the EE serial port (`sio_write`) is live. The layer writes every line to serial and to a buffered `bin/log.txt`, and hooks libc's `_ps2sdk_write` so Tyra's own `TYRA_LOG` output reaches both sinks too (verified in `examples/hello`, including after Tyra's `Engine` resets the IOP). Ruled out: [ps2dev/ps2sdk#332](https://github.com/ps2dev/ps2sdk/issues/332) was a PCSX2 bug fixed in 2022 ([PCSX2/pcsx2#7007](https://github.com/PCSX2/pcsx2/pull/7007)).
  Follow-ups:
  - [ ] `run-project --follow`: stream `bin/log.txt` to the terminal until the emulator exits (the GUI does the same with its own tail).
  - [ ] Timestamps and/or frame numbers in the line format (needs a decision on the clock source and a format-version bump for the GUI).
  - [ ] Load `Log::applySpec` from a file the GUI can edit, so levels change without rebuilding.
  - [ ] Thread safety (currently main-thread only); the file buffer is a single static.
  - [ ] Check high log volume: file flush opens and closes `log.txt` each time it is non-empty; measure at high rates and consider a longer flush interval.
  - [ ] PCSX2's `-logfile <path>` and `-batch` flags via `PCSX2_ARGS`, so the emulator's own log also lands in a known file.
  - [ ] Real hardware: serial output is slow at 38400 baud and `host:` does not exist; decide sink defaults for non-emulator builds.
  - [ ] A `[Tyra]` category for raw stdout lines, if partial-line chunks from the hook prove reliable enough to tag.
