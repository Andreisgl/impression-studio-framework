#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make inside the pinned toolchain container. Any arguments are passed to
# make. Usage: scripts/make.sh [target...]   (default target builds Tyra, then
# the framework). Examples: scripts/make.sh    scripts/make.sh clean-tyra
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v docker >/dev/null 2>&1 || { echo "error: docker not found in PATH" >&2; exit 1; }

git submodule update --init --recursive

docker compose run --rm -T toolchain make "$@"
