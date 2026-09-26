#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make in the project folder inside the toolchain container; arguments go to
# make. With no arguments it builds the project (like build-project.sh).
# Usage: scripts/make.sh [make args]     Project: PROJECT_DIR in impression.local.conf.
# For the engine or framework libraries use scripts/imp.sh build-engine|build-framework.
# Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment (docs/tooling-contract.md).
set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/imp.sh" make "$@"
