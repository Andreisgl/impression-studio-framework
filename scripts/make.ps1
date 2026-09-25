# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs make inside the pinned toolchain container. Any arguments are passed to
# make. Usage: scripts\make.ps1 [target...]   (default target builds Tyra, then
# the framework). Examples: scripts\make.ps1    scripts\make.ps1 clean-tyra
$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker not found in PATH'
}

git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw "git submodule update failed (exit code $LASTEXITCODE)" }

docker compose run --rm -T toolchain make @args
if ($LASTEXITCODE -ne 0) { throw "make failed (exit code $LASTEXITCODE)" }
