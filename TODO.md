# TODO

## Tooling
- [ ] **Projects outside this repo.** Projects must live inside this repo (like `examples/hello`), because the container mounts only the repo root (`docker-compose.yml`: `.:/work`). External game repos will need a design decision later, probably each carrying the framework as a submodule. Decide before the GUI opens user projects. (`scripts/lib/common.*` `resolve_project` currently rejects paths outside the repo.)
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
