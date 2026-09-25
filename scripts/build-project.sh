#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds a project completely (Tyra, the framework, then the project) inside the
# toolchain container. Usage: scripts/build-project.sh <project-dir>
# Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment.
# On success the last stdout line is IMPRESSION_ELF=<absolute path to the ELF>.
# See docs/tooling-contract.md.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

case "${1:-}" in
    -h | --help)
        sed -n '5,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac
[ "$#" -eq 1 ] || die "$EXIT_USAGE" "usage: build-project.sh <project-dir>"

resolve_project "$1"

status=0
"$IMPRESSION_ROOT/scripts/make.sh" -C "$PROJECT_REL" || status=$?
if [ "$status" -ne 0 ]; then
    [ "$status" -eq "$EXIT_ENV" ] && exit "$EXIT_ENV"
    die "$EXIT_FAIL" "build failed for $PROJECT_REL"
fi

find_elf
echo "IMPRESSION_ELF=$ELF"
