# TODO

## Tooling
- [ ] **Projects outside this repo.** Projects must live inside this repo (like `examples/hello`), because the container mounts only the repo root (`docker-compose.yml`: `.:/work`). External game repos will need a design decision later, probably each carrying the framework as a submodule. Decide before the GUI opens user projects. (`scripts/lib/common.*` `resolve_project` currently rejects paths outside the repo.)
- [ ] **Real-time program output.** Live output is integral to the development cycle. Current state: `TYRA_LOG` goes to stdout by default and never reaches PCSX2's log (tested on PCSX2 2.6.3, even with `EnableEEConsole = true`). Workaround in use: `EngineOptions::writeLogsToFile = true` writes `<project>/bin/log.txt`, and measured behaviour is real time (a new line appears in the file as it is logged, checked at 0.5 s polling). Open work:
  - [ ] Make file logging the documented default for projects, and have `run-project` / the GUI tail `bin/log.txt` live (`Get-Content -Wait` / `tail -f`). Verify it keeps up with high log volume (an unthrottled loop produced 260 KB in 30 s).
  - [ ] **Route stdout to the EE serial port (fix found, not yet in the framework).** Control experiment (pure ps2sdk ELF, no Tyra, PCSX2 2.6.3, EE console on): `printf` never reaches PCSX2's log, but `sio_puts` does, once per line in real time. So Tyra's IOP reset is not the cause. Setting libc's write hook makes plain `printf` (and therefore `TYRA_LOG`) appear in real time:
    ```cpp
    extern "C" {
    #include <ps2sdkapi.h>   // declares int (*_ps2sdk_write)(int, const void*, int); no extern "C" guard in the header
    }
    static int sioWrite(int fd, const void* buf, int n) {
      return (fd == 1 || fd == 2) ? (int)sio_write(const_cast<void*>(buf), n) : -1;
    }
    // at startup: sio_init(38400, 0, 0, 0, 0); _ps2sdk_write = sioWrite; setvbuf(stdout, NULL, _IOLBF, 0);
    ```
    Gotchas found: the translation unit that touches `_ps2sdk_write` needs `-G0` (else `R_MIPS_GPREL16` link error); something calling `fileXioInit()` would replace the hook (Tyra does not). Still to verify inside a Tyra game (Tyra's `Engine` construction resets the IOP; the hook is EE-side so it should survive). Plan: implement as a "serial sink" in the IMP_LOG layer, keep `bin/log.txt` as the other sink. Ruled out: [ps2dev/ps2sdk#332](https://github.com/ps2dev/ps2sdk/issues/332) was a PCSX2 bug fixed in 2022 ([PCSX2/pcsx2#7007](https://github.com/PCSX2/pcsx2/pull/7007)).
  - [ ] Consider PCSX2's `-logfile <path>` and `-batch` flags (via `PCSX2_ARGS`) so the emulator's own log also lands in a known file.
  - [ ] If a core patch is needed, make it in the Tyra fork on its own branch and consider an upstream issue.
  - [ ] Add a note about `bin/log.txt` and logging setup to the README.
