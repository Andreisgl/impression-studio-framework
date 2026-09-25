#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds Tyra's engine library (extern/tyra/engine/bin/libtyra.a) inside the
# pinned toolchain container. Run once per clone, and again only after the Tyra
# submodule changes. Usage: scripts/build-tyra.sh [--clean]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v docker >/dev/null 2>&1 || { echo "error: docker not found in PATH" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "error: 'docker compose' plugin not available" >&2; exit 1; }

git submodule update --init --recursive

if [ ! -f extern/tyra/Makefile.base ]; then
    echo "error: extern/tyra is empty; submodule checkout failed" >&2
    exit 1
fi

if grep -q $'\r' extern/tyra/Makefile.base; then
    echo "warning: extern/tyra/Makefile.base has CRLF line endings; make will likely fail." >&2
    echo "         Fix: git -C extern/tyra config core.autocrlf false && git -C extern/tyra checkout -- ." >&2
fi

if [ "${1:-}" = "--clean" ]; then
    docker compose run --rm -T toolchain make -C extern/tyra/engine cleaner
fi

docker compose run --rm -T toolchain make -C extern/tyra/engine

lib=extern/tyra/engine/bin/libtyra.a
if [ ! -f "$lib" ]; then
    echo "error: build finished but $lib was not produced" >&2
    exit 1
fi
echo "OK: $lib"
