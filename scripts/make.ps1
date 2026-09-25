# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make inside the pinned toolchain container. Any arguments are passed to
# make. With no arguments it builds Tyra's library, then the framework.
# Usage: scripts\make.ps1 [target...]
# Examples: scripts\make.ps1    scripts\make.ps1 tyra    scripts\make.ps1 clean-tyra
# Exit codes: 0 ok, 1 build failed, 3 environment (see docs/tooling-contract.md).
$ErrorActionPreference = 'Stop'

function Stop-Make {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("error: $Message")
    exit $Code
}

Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Stop-Make 3 'docker not found in PATH'
}
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Make 3 "'docker compose' plugin not available" }

git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { Stop-Make 3 'git submodule update failed' }

if (-not (Test-Path 'extern/tyra/Makefile.base')) {
    Stop-Make 3 'extern/tyra is empty; submodule checkout failed'
}

$makeArgs = $args
docker compose run --rm -T toolchain make @makeArgs
# make's own failure code is 2, which would collide with "usage"; report 1.
if ($LASTEXITCODE -ne 0) { Stop-Make 1 "make failed (exit code $LASTEXITCODE)" }

if ($makeArgs.Count -eq 0) {
    $libs = 'extern/tyra/engine/bin/libtyra.a', 'bin/libimpression.a'
    foreach ($lib in $libs) {
        if (-not (Test-Path $lib)) { Stop-Make 1 "build finished but $lib was not produced" }
    }
    Write-Host "OK: $($libs -join ' ')"
}
