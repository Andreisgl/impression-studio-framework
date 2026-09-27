<!--
Copyright 2026 Andrei Segal
SPDX-License-Identifier: Apache-2.0
-->

# Notes on porting the Tyra fork to current ps2dev

For anyone reviewing or helping with this work. It lists every dependency, every
change and every open question, and says which statements were **verified** (run and
observed) and which are **inferred** (read from documentation or source, not run).
Written 2026-09-26. Status: **the port builds and boots; VU rendering is not yet
validated** (nothing has been drawn through the ported VU programs).

## 1. Why a port

The Tyra fork (`Andreisgl/tyra`, from `h4570/tyra` master `c59f406`) builds only in
a mid-2022 ps2dev environment. Current ps2dev differs in ways that break it:

| Problem | Evidence |
|---|---|
| `bin2s` no longer exists. Tyra's `Makefile.base` calls `$(PS2SDK)/bin/bin2s` to embed 10 IRX modules. | ps2sdk commit `8dafdfde` (2024-01-21), "Remove bin2s and bin2o in favor of bin2c". Verified: no `bin2s` in the current image. |
| Tyra's own `Dockerfile` clones ps2dev `master` unpinned, so building it today gives the current environment, not the 2022 one. | Read from `Dockerfile`; not built. **Inferred** that it therefore fails. |
| The official `ps2dev/ps2dev` image is Alpine (musl) with GCC 15.2. | Verified in the image. |
| Sony's `vcl` is a 32-bit glibc executable, so it cannot run on Alpine without extra work. | Verified with `file` on `assets/vcl`: ELF 32-bit i386, dynamically linked against `/lib/ld-linux.so.2` (glibc). |

The repository's launchers now default to the ported toolchain (the official
`ps2dev/ps2dev` image, GCC 15.2, `docker/Dockerfile.modern`). The source-built July
2022 snapshot (`docker/Dockerfile.ps2dev`, GCC 11.3.0, known to work with unported
Tyra) remains available as `IMPRESSION_TOOLCHAIN=snapshot`, with its own container.
Consequence: the default toolchain builds only the port, so the framework's recorded
`extern/tyra` pointer (still upstream `c59f406`) is not buildable by default until it
is moved to a pushed port commit (a deliberately deferred step).

## 2. Dependencies (modern toolchain)

| Piece | Version / source | License | Notes |
|---|---|---|---|
| Base image | `ps2dev/ps2dev@sha256:1511fde1e42e2c8c192e08a308d9c90d3d69613f6c8022ec71aac7202d477336` | (ps2dev) | Alpine 3.24. **Verified:** GCC 15.2.0, `dvp-as`, `bin2c`, `openvcl`, `masp`, libpng, zlib, all IRX modules Tyra embeds. Binutils 2.45.1 and newlib 4.5.0 are from the ps2toolchain READMEs (inferred). |
| `openvcl` | 0.4.0, `github.com/ps2dev/openvcl` tag `v0.4.0` | AFL 2.0 | Built by ps2dev (`ps2toolchain-dvp/scripts/003-openvcl.sh`, config `ps2toolchain-dvp-config.sh`). **Unmodified.** Reports `OpenVCL Version 0.4.0`. |
| `masp` | 0.1.16, `github.com/ps2dev/masp` | (see repo) | In the image, **not used** by this port. |
| `dvp-as` | `ps2dev/binutils-gdb` ref `dvp-v2.45.1` | GPL | **Unmodified.** The 2022 snapshot used a 2.14-based `dvp-as`; the 2024 history of that branch shows assembler changes (default PIC), so behaviour may differ. |
| `vclpp` | `github.com/glampert/vclpp` commit `6d787b6` (2016), built in `docker/Dockerfile.modern` | MIT | **Not part of ps2dev.** See section 5. |
| Alpine packages | `bash make git coreutils findutils sed grep libstdc++ libgcc` | various | `libstdc++`/`libgcc` are needed because the image ships `openvcl` without its C++ runtime (verified: it fails to start without them). |
| Tyra fork | `Andreisgl/tyra`, local branch `port/ps2dev-2.0` (commits `c368301`, `22dd639`, `333fd2c`, `0031aeb` and `b026f86`, **not pushed**) | Apache 2.0 (stated in headers/README; the repo has no LICENSE file since 2022) | |
| Framework | this repository | Apache 2.0 | |

## 3. The VU program pipeline

Tyra's 15 vector-unit (VU1) programs are the "graphic binaries". They are built in
four stages (rules in `Makefile.base`):

```
X.vclpp --vclpp--> X.vcl --openvcl--> X.vsm --dvp-as--> X.o   (linked into libtyra.a)
```

- `.vclpp`: the source. VU assembly with `#include`, `#define`, and `#macro`
  definitions (101 macros), invoked as `MacroName{ arg, arg }`.
- `.vcl`: the same with preprocessing expanded, in VCL syntax (`.syntax new`,
  `--enter`/`--endenter`, `--cont`, `--barrier`, `#vuprog`).
- `.vsm`: final scheduled VU assembly with real registers.
- The optimizer stage was Sony's `vcl` (proprietary); it is now OpenVCL.

To reproduce one program by hand, inside the toolchain container, from
`extern/tyra/engine`:

```
vclpp src/renderer/3d/pipeline/static/core/programs/cull/stapip_cull_c_vu1.vclpp /tmp/a.vcl
openvcl /tmp/a.vcl > /tmp/a.vsm
dvp-as /tmp/a.vsm -o /tmp/a.o
```

**Verified:** all 15 programs go through all three commands and assemble.
**Not verified:** that the resulting microcode behaves like the `vcl`-generated one.
No comparison against the old output was made (dropped by decision), and nothing
has rendered yet.

## 4. Changes

### 4.1 Tyra fork, branch `port/ps2dev-2.0` (commits `c368301`, `22dd639`, `333fd2c`, `0031aeb` and `b026f86`)

1. **`Makefile.base`**: `BIN2S` becomes `BIN2C`; the `.irx-em` rule generates
   `X.o.c` with `bin2c <irx> <out.c> <label>` and compiles it with the EE `gcc`;
   `VCL := openvcl`. `bin2c` emits `size_<label>` and `<label>[]`, the symbols
   `irx_loader.cpp` declares. **Verified at runtime:** the 10 modules load.
2. **The `PerformClipCheck` macro** (in `vcl_sml.i` at the time, now in `vu_macros.i`,
   see item 6): its first instruction changed from
   `clipw.xyz t_vertex, t_vertex` to `clipw.xyz t_vertex, t_vertex[w]`.
   *What the macro does:* CLIPw compares the vertex's xyz with its w and records the
   result in the clip flag register; `fcand` tests those flags against a mask; the
   result (`0x7FFF` plus that 0 or 1) is stored in the w of the vertex's output slot,
   where bit 15 is the GS "ADC" bit that makes the GS skip the triangle.
   *Why it changed:* OpenVCL failed the 9 programs that use it (the four `dynpip_*`,
   `mcpip_cull` and the four `stapip_cull_*`) with
   `Invalid argument (clipw.xyz vertex1, >>> vertex1 <<<)`. Its instruction table
   (`VuInstructionInfo.cpp`) types `clipw` as `"vf:dest,vf:wcomp"`; `wcomp` is handled
   as a component selector, and under `.syntax new` a selector on an alias is only
   accepted as `alias[w]`. Tried and rejected: `vw`, `v.w`, `v[xyz], v[w]`, no `.xyz`,
   `clip`, `vf00`. *Effect:* the assembled instruction is the normal
   `clipw.xyz VF13, VF13w`. The `[w]` only names the component CLIPw always reads, so
   behaviour should be unchanged. **Not compared** with what `vcl` generated for the
   same source (`vcl` is not available in the port); no rendering test yet.
   This is the only edit that changes a macro's text for the sake of a tool; everything
   else about the macro is as before.
3. **`stapip_cull_td_vu1.vclpp`**: each vertex is now loaded, computed and stored
   in sequence instead of loading all three first and storing all three last.
   OpenVCL reported `Float registers: 31 available, 41 needed` and a peak of 32 live
   at once (22 constants live across the whole loop); it failed even with `-d`
   (no scheduling), `-C`, `-L` and `-t5000`, so it is register pressure, not the
   optimizer. The stores and the clip-flag write touch the same addresses in the
   same order. **Not verified:** rendering, and whether the scheduler now
   overlaps the three vertices as well as before (throughput may differ).
4. **`renderer_3d_pipeline.hpp`**: `#include <functional>`. GCC 15's libstdc++ no
   longer provides `std::function`/`std::bind` transitively. This was the only
   engine compile error.
5. **`FileUtils::fromCwd`**: adds `/` when `getcwd()` does not end in `/`, `\` or
   `:`. Older ps2sdk's `getcwd()` gave a device prefix (`host:`); the current one
   gives the whole directory (`host:/D:/.../bin`), so paths became
   `.../binlog.txt`. Found because the framework's `log.txt` was not created.
   This affects every `fromCwd` resource load in Tyra and the demo.
   **Verified:** `host:` under PCSX2. **Not verified:** `mass:`, real hardware.
6. **`vu_macros.i` replaces `vcl_sml.i`.** New file (`engine/src/renderer/3d/pipeline/shared/`),
   nine macros written from the instruction set described in the VU User's Manual:
   `MatrixLoad`, `MatrixMultiply`, `MatrixMultiplyVertex`, `VertexPersCorr`,
   `ResetClipFlags`, `PerformClipCheck`, `ScaleVertexToGSFormat`,
   `PerformTexturePerspectiveCorrection`, `FixColor` (the only nine the programs use;
   the other 68 macros of the Sony library are gone). The 14 programs that included
   `vcl_sml.i` now include `vu_macros.i` (the 15th, `draw_finish`, includes neither).
   `vcl_sml.i` is deleted. **Verified:** all 15 programs produce **byte-identical**
   `.vsm` files from OpenVCL before and after the switch, so the macros expand to
   exactly the same instructions. For macros this small (a matrix multiply, a
   perspective divide, a clamp) the instruction set dictates the sequence; identical
   output does not by itself settle any copyright question. The file must use LF line
   endings: `vclpp` does not recognise `#endmacro` followed by a carriage return.
   The macro names, arguments and the temporary alias `adcBit` are unchanged, because
   the programs depend on them.
7. **`assets/vcl` deleted.** Sony's `vcl` binary, unused by the port build. It remains
   in the fork's history (see section 7).
8. **`Dockerfile` and `README.MD`** (commits `333fd2c` and `0031aeb`): the Dockerfile no
   longer downloads `assets/vcl`, and it no longer compiles ps2dev from source. It now
   derives from `ps2dev/ps2dev@sha256:1511fde1...` (the digest used for the whole port)
   and adds `vclpp` (pinned commit `6d787b6`), the GNU tools `Makefile.base` uses and
   the C++ runtime that `openvcl`/`vclpp` need. The README's "Built With" lists
   OpenVCL instead of Sony VCL. **Verified:** the image builds, and from a clean copy
   of the fork (no `assets/vcl`, no earlier build output) `make -C engine`,
   `make -C tutorials/01-hello` and `make -C tutorials/05-animation` succeed using only
   that image. **Not verified:** rendering. The PS2DEV pin cannot simply be the
   `v2.0.0` tag, see section 6.
9. **CI, compose, template, VS Code tasks and install docs** (commit `b026f86`): nothing
   points at the `h4570/tyra` image any more (upstream project links remain). The
   image is built from the fork's `Dockerfile` and tagged `tyra`. CI workflows
   (`master-build.yml`, `pr-build-check.yml`) now run `docker build -t tyra .` and
   execute every `make` inside it with `--user "$(id -u):$(id -g)"`, replacing
   `container: h4570/tyra` and the `apt` steps. The `Dockerfile` gained `rsync` (the VS
   Code tasks copy sources into the container with it; the official image lacks it,
   the old one had it). `docker-compose.yml` builds the Dockerfile; `template/Dockerfile`
   derives from the locally built `tyra` image; both VS Code task files start the log
   listener from `tyra`; `docs/install` says `docker compose build` instead of
   `docker pull`. **Verified:** `docker compose build`; the template image builds on
   top of it; `rsync`, `killall`, `ps2client` and `adpenc` are present; the exact
   commands from `pr-build-check.yml` (engine, tutorial 05, demo, serial, non-root,
   clean copy) exit 0 with no errors (330 s). Earlier, all 11 tutorials and the demo
   built from clean. **Not verified:** the workflows on GitHub Actions itself (the YAML
   was edited structurally and read, not run or linted). **Left as is:** the template's
   VS Code task still runs `git clone https://github.com/h4570/tyra.git` into `/tyra`,
   i.e. the upstream engine without this port, and the install docs still clone
   upstream; both need the fork's URL and branch once it is published.

### 4.2 This repository (commit `afe0ba7`)

- `docker/Dockerfile.modern`, and the `IMPRESSION_TOOLCHAIN` switch (its own image and
  container per flavour). It was opt-in (`modern`) while the port was unverified; the
  default is now `modern`, and `snapshot` selects the old source-built toolchain.
- The launchers no longer run `git submodule update` on an existing Tyra checkout
  (it would reset a fork branch under development).
- `src/log_serial.cpp` overrides newlib's `_write` (fd 1 and 2 go to the log sinks,
  other descriptors go to `_ps2sdk_write`). Current ps2sdk made `_ps2sdk_write` a
  function instead of a function pointer, so the earlier hook no longer compiled.
  The override replaces a libcglue function; registering a file-descriptor
  handler with libcglue's fdman may be the cleaner design (open question).
- `src/log.cpp` reports why `log.txt` cannot be opened, once, on the serial console.

### 4.3 What was **not** changed

Nothing in ps2dev was modified: not `openvcl`, `masp`, `dvp-as`, `bin2c`, the
compiler, or ps2sdk. `ps2dev/openvcl` v0.4.0 was cloned to a scratch folder only to
read its source; it was not edited or rebuilt.

## 5. Why `vclpp` is in the image although it is not part of ps2dev

Tyra's VU sources use a macro syntax that only `vclpp` understands: definitions
`#macro Name: a, b ... #endmacro`, invocations `Name{ a, b }`, plus `#include` and
`#define`. OpenVCL has no equivalent: it can call `gasp`/`masp` (`-g`, GASP
`.macro` syntax) or `cpp` (`-G`), neither of which understands `#macro`. The
original pipeline already ran `vclpp` before `vcl`, so keeping it changes nothing in
Tyra's sources: it is the smallest change. It is small, MIT-licensed, built from a
pinned commit, and compiled cleanly with GCC 15. **Not tested:** converting the 101
macros to MASP or `cpp` syntax to drop `vclpp`; that would touch every macro
definition and invocation.

## 6. OpenVCL observations worth a second opinion

- The ps2sdk sample `samples/draw/vu1/draw_3D.vcl` (old syntax, `clipw.xyz vertex,
  vertex`) fails in OpenVCL 0.4.0 with the same error; that sample's Makefile
  prefers the original `vcl` and ships a pre-generated `.vsm`. This may be an
  OpenVCL bug or limitation worth reporting to `ps2dev/openvcl`; no report was made.
- `openvcl` in the official image cannot start without `libstdc++` and `libgcc`.
- `openvcl --cost`, `--cost-compare` and `--show-reg-alloc` exist and were not
  used beyond `--show-reg-alloc`.
- **ps2dev `v2.0.0` does not build OpenVCL.** Read from the tagged config files (not
  built): at `v2.0.0` (2026-05-17) `ps2toolchain-dvp` builds only binutils
  (`dvp-v2.45.1`); the `OpenVCL v0.4.0` and `masp v0.1.16` steps exist on that
  repository's `main` (OpenVCL `v0.4.0` was tagged 2026-05-18, a day after ps2dev
  `v2.0.0`). The EE side at `v2.0.0` is GCC `ee-v15.2.0`, newlib `ee-v4.6.0`,
  binutils `ee-v2.45.1`. The official image used for the port has OpenVCL, so it was
  built from a later state. Consequence: a Dockerfile that pins the from-source build
  to `v2.0.0` would produce a toolchain without `openvcl`, and the port's VU build
  would fail. ps2dev's `v2.0.0` script passes the tag to each component, and every
  component has a `v2.0.0` tag (gsKit no longer has its own script), so tag pinning
  is mechanically possible, but not sufficient by itself. The fork's Dockerfile therefore
  uses the official image pinned by digest instead of a from-source build.

## 7. Sony-copyrighted material in the fork

Two tracked files were Sony's, found by searching the whole repository:

| File | What | Status on `port/ps2dev-2.0` |
|---|---|---|
| `assets/vcl` | Sony's `vcl` 1.4beta7 binary (added upstream in `c40558b`, 2023-11-25, "move vcl from my server to github repo"; no origin or license recorded) | **Deleted.** The port never ran it. |
| `engine/src/renderer/3d/pipeline/shared/vcl_sml.i` | Sony's VCL Standard Macros Library, header "Copyright (C) 2002-2004, Sony Computer Entertainment America Inc. All rights reserved" (77 macros, 1430 lines; 9 used) | **Deleted**, replaced by `vu_macros.i` (item 6 above). |

Done in commit `333fd2c`: the fork's `Dockerfile` no longer downloads `assets/vcl` and the
`README.MD` no longer lists Sony VCL. Still to update: CI workflows, `template/` and docs.

Neither file had a license in the repository. Deleting them from the branch stops new
commits from carrying them, but they remain in the fork's history, in upstream
`h4570/tyra` and in other forks; only a history rewrite (for example `git filter-repo`)
followed by a force-push would remove them from the fork, and it would not touch
upstream or other forks. This is not legal advice.

## 8. Open questions for reviewers

1. Is the `v[w]` edit to `PerformClipCheck` semantically identical to the original for the hardware? (It assembles to the normal `clipw.xyz VFx, VFxw`; nothing was compared with `vcl` output.)
2. Does the reordered `stapip_cull_td_vu1` schedule as well? (Compare `openvcl --cost`.)
3. Does the new `dvp-as` (binutils 2.45.1 dvp) accept and link Tyra's objects correctly on
   hardware, given the 2024 default-PIC change?
4. Is overriding `_write` acceptable, or should stdout be redirected through libcglue's fdman?
5. Should the `clipw` failure, including the ps2sdk sample, be reported to `ps2dev/openvcl`?
6. Please review `vu_macros.i` against the VU manual: does each macro do what its comment says, and are the clobbered registers (ACC, Q, I, VI01) documented correctly?
7. *(Decided, review welcome.)* The fork's `Dockerfile` derives from the official `ps2dev/ps2dev` image pinned by digest, which contains `openvcl`. Is a digest the right pin? It only moves when someone updates it deliberately.

## 9. Repositories and artifacts touched

**Committed or staged (the only two repositories changed):**
- `Andreisgl/tyra` (your fork), local branch `port/ps2dev-2.0`, **not pushed**. Reachable
  through the framework's submodule folder `extern/tyra`.
- This framework repository (`impression-studio-framework`), on its current branch.

**Not modified:** upstream `h4570/tyra`; `ps2dev/*` (`openvcl`, `masp`, `ps2sdk`,
toolchain, images); `glampert/vclpp`; PCSX2 and its configuration; the
`flying-in-deceit` project (only listed for asset ideas).

**Local, not in any repository:** Docker images `impression/ps2dev:2022-07`,
`impression/toolchain:dev`, `impression/toolchain:modern` (plus the pulled
`ps2dev/ps2dev` and `h4570/tyra` images) and containers `impression-dev` and
`impression-dev-modern`; scratch clones of ps2dev repositories in a temporary
folder; PCSX2's own log files.
