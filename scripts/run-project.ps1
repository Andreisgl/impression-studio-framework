# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs a project's ELF in PCSX2. The emulator location comes from PCSX2_PATH in
# impression.local.conf (or the environment). Does not build unless asked.
# Usage: scripts\run-project.ps1 <project-dir> [-Build] [-Restart] [-Wait] [-DryRun]
#   -Build    build the project first (same as build-project.ps1)
#   -Restart  stop a running instance of the same emulator first
#   -Wait     stay in the foreground until the emulator exits (default: detach)
#   -DryRun   print the command as IMPRESSION_CMD=... instead of launching
# Exit codes: 0 ok, 1 build/launch failed, 2 usage, 3 environment (e.g. no PCSX2_PATH).
# Detached launches print IMPRESSION_PID=<pid>. See docs/tooling-contract.md.
param(
    [Parameter(Position = 0)][string]$Project,
    [switch]$Build,
    [switch]$Restart,
    [switch]$Wait,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

if ($Help) {
    Get-Content $PSCommandPath -TotalCount 12 | Select-Object -Skip 3 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 0
}

$config = Get-ImpressionConfig
$pcsx2Path = $config['PCSX2_PATH']
if ([string]::IsNullOrEmpty($pcsx2Path)) {
    Stop-Script $script:ExitEnv 'PCSX2_PATH is not set. Copy impression.local.conf.example to impression.local.conf and set it.'
}

$proj = Resolve-ImpressionProject $Project

if ($Build) {
    & (Join-Path $PSScriptRoot 'build-project.ps1') $proj.Rel
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$elf = Find-ImpressionElf $proj.Abs

# Locate the emulator: PCSX2_PATH is either the executable or its directory.
$emu = $null
if (Test-Path -LiteralPath $pcsx2Path -PathType Leaf) {
    $emu = (Resolve-Path -LiteralPath $pcsx2Path).Path
} elseif (Test-Path -LiteralPath $pcsx2Path -PathType Container) {
    foreach ($name in 'pcsx2-qt.exe', 'pcsx2-qtx64.exe', 'pcsx2-qtx64-avx2.exe', 'pcsx2x64.exe', 'pcsx2.exe') {
        $candidate = Join-Path $pcsx2Path $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $emu = (Resolve-Path -LiteralPath $candidate).Path; break }
    }
}
if (-not $emu) { Stop-Script $script:ExitEnv "PCSX2 executable not found at PCSX2_PATH=$pcsx2Path" }

# Old wx-based builds take --elf=<file>; the Qt builds take -elf <file>.
# Start-Process does not quote array elements, so paths are quoted by hand.
$emuDir = Split-Path $emu -Parent
$emuName = [IO.Path]::GetFileNameWithoutExtension($emu)
$isLegacy = ($emuName -in 'pcsx2', 'pcsx2x64') -and -not (Test-Path -LiteralPath (Join-Path $emuDir 'qt.conf'))
$argList = @()
if (-not [string]::IsNullOrWhiteSpace($config['PCSX2_ARGS'])) {
    $argList += $config['PCSX2_ARGS'].Trim() -split '\s+'   # split on whitespace, no quoting support
}
if ($isLegacy) { $argList += "--elf=`"$elf`"" } else { $argList += '-elf', "`"$elf`"" }

if ($DryRun) {
    Write-Output "IMPRESSION_CMD=`"$emu`" $($argList -join ' ')"
    exit 0
}

if ($Restart) {
    Get-Process -Name $emuName -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

if ($Wait) {
    Start-Process -FilePath $emu -ArgumentList $argList -Wait
    exit 0
}

$process = Start-Process -FilePath $emu -ArgumentList $argList -PassThru
Write-Output "IMPRESSION_PID=$($process.Id)"
