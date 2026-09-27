# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds a project completely (Tyra, the framework, then the project) inside the
# toolchain container. Usage: scripts\build-project.ps1 [project-dir]
# Without an argument the project is PROJECT_DIR from impression.local.conf, else
# examples/hello. Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment.
# On success the last stdout line is IMPRESSION_ELF=<absolute path to the ELF>.
# See docs/tooling-contract.md.
param(
    [Parameter(Position = 0)][string]$Project,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Select-Toolchain

if ($Help) {
    Get-Content $PSCommandPath -TotalCount 9 | Select-Object -Skip 3 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

$config = Get-ImpressionConfig
$projectAbs = Resolve-ImpressionProject $Project $config
Confirm-Container $projectAbs

# The container prints a project-relative path; tools get an absolute host path.
Invoke-ContainerImp build | ForEach-Object {
    if ($_ -match '^IMPRESSION_ELF=(.+)$') { "IMPRESSION_ELF=$projectAbs\" + ($Matches[1] -replace '/', '\') } else { $_ }
}
exit $LASTEXITCODE
