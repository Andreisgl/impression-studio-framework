# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make in the project folder inside the toolchain container; arguments go to
# make. With no arguments it builds the project (like build-project.ps1).
# Usage: scripts\make.ps1 [make args]     Project: PROJECT_DIR in impression.local.conf.
# For the engine or framework libraries use scripts\imp.ps1 build-engine|build-framework.
# Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment (docs/tooling-contract.md).
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'imp.ps1') make @args
exit $LASTEXITCODE
