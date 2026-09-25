# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Builds Tyra's engine library (extern/tyra/engine/bin/libtyra.a) inside the
# pinned toolchain container. Run once per clone, and again only after the Tyra
# submodule changes. Usage: scripts\build-tyra.ps1 [-Clean]
param([switch]$Clean)

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

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $makefileBase))
if ($bytes -contains 13) {
    Write-Warning "$makefileBase has CRLF line endings; make will likely fail."
    Write-Warning 'Fix: git -C extern/tyra config core.autocrlf false; git -C extern/tyra checkout -- .'
}

if ($Clean) {
    Invoke-Native 'make cleaner' { docker compose run --rm -T toolchain make -C extern/tyra/engine cleaner }
}

Invoke-Native 'make' { docker compose run --rm -T toolchain make -C extern/tyra/engine }

$lib = 'extern/tyra/engine/bin/libtyra.a'
if (-not (Test-Path $lib)) {
    throw "build finished but $lib was not produced"
}
Write-Host "OK: $lib"
