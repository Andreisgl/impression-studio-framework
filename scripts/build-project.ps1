# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds a project completely (Tyra, the framework, then the project) inside the
# toolchain container. Usage: scripts\build-project.ps1 <project-dir>
# Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment.
# On success the last stdout line is IMPRESSION_ELF=<absolute path to the ELF>.
# See docs/tooling-contract.md.
param(
    [Parameter(Position = 0)][string]$Project,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

if ($Help) {
    Get-Content $PSCommandPath -TotalCount 8 | Select-Object -Skip 3 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

$proj = Resolve-ImpressionProject $Project

try {
    & (Join-Path $PSScriptRoot 'make.ps1') -C $proj.Rel
    $status = $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("error: $($_.Exception.Message)")
    $status = $script:ExitFail
}
if ($status -ne 0) {
    if ($status -eq $script:ExitEnv) { exit $script:ExitEnv }
    Stop-Script $script:ExitFail "build failed for $($proj.Rel)"
}

$elf = Find-ImpressionElf $proj.Abs
Write-Output "IMPRESSION_ELF=$elf"
