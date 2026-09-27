#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds a project completely (Tyra, the framework, then the project) inside the
# toolchain container. Usage: scripts/build-project.sh [project-dir]
# Without an argument the project is the PROJECT_DIR environment variable, else
# project/. Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment.
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
[ "$#" -le 1 ] || die "$EXIT_USAGE" "usage: build-project.sh [project-dir]"

resolve_project "${1:-}"
load_project_config
ensure_container

# The container prints a project-relative path; tools get an absolute host path.
container_imp build | sed -u "s|^IMPRESSION_ELF=|IMPRESSION_ELF=$PROJECT_ABS/|"
