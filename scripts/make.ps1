# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make inside the pinned toolchain container. Any arguments are passed to
# make. With no arguments it builds Tyra's library, then the framework.
# Usage: scripts\make.ps1 [target...]
# Examples: scripts\make.ps1    scripts\make.ps1 tyra    scripts\make.ps1 clean-tyra
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param([string]$Description, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Description failed (exit code $LASTEXITCODE)" }
}

Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker not found in PATH'
}
Invoke-Native 'docker compose check' { docker compose version | Out-Null }

Invoke-Native 'git submodule update' { git submodule update --init --recursive }

$makefileBase = 'extern/tyra/Makefile.base'
if (-not (Test-Path $makefileBase)) {
    throw 'extern/tyra is empty; submodule checkout failed'
}

$makeArgs = $args
Invoke-Native 'make' { docker compose run --rm -T toolchain make @makeArgs }

if ($makeArgs.Count -eq 0) {
    $libs = 'extern/tyra/engine/bin/libtyra.a', 'bin/libimpression.a'
    foreach ($lib in $libs) {
        if (-not (Test-Path $lib)) { throw "build finished but $lib was not produced" }
    }
    Write-Host "OK: $($libs -join ' ')"
}
