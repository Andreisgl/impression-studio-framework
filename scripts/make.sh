#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make inside the pinned toolchain container. Any arguments are passed to
# make. With no arguments it builds Tyra's library, then the framework.
# Usage: scripts/make.sh [target...]
# Examples: scripts/make.sh    scripts/make.sh tyra    scripts/make.sh clean-tyra
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Exit 3 = environment problem (see docs/tooling-contract.md).
command -v docker >/dev/null 2>&1 || { echo "error: docker not found in PATH" >&2; exit 3; }
docker compose version >/dev/null 2>&1 || { echo "error: 'docker compose' plugin not available" >&2; exit 3; }

git submodule update --init --recursive

if [ ! -f extern/tyra/Makefile.base ]; then
    echo "error: extern/tyra is empty; submodule checkout failed" >&2
    exit 3
fi

status=0
docker compose run --rm -T toolchain make "$@" || status=$?
# make's own failure code is 2, which would collide with "usage"; report 1.
if [ "$status" -ne 0 ]; then
    echo "error: make failed (exit code $status)" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    for lib in extern/tyra/engine/bin/libtyra.a bin/libimpression.a; do
        if [ ! -f "$lib" ]; then
            echo "error: build finished but $lib was not produced" >&2
            exit 1
        fi
    done
    echo "OK: extern/tyra/engine/bin/libtyra.a bin/libimpression.a"
fi
