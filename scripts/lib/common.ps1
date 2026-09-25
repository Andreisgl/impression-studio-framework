# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Shared helpers for build-project.ps1 and run-project.ps1. Dot-sourced, not executed.
# The contract these scripts expose to tools is documented in docs/tooling-contract.md.

$script:ImpressionRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$script:ExitFail = 1   # the build or launch itself failed
$script:ExitUsage = 2  # bad arguments, unknown project, missing or ambiguous ELF
$script:ExitEnv = 3    # environment problem: docker, git or PCSX2 missing or misconfigured

# Stop-Script <exit-code> <message>: message to stderr, then exit.
function Stop-Script {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("error: $Message")
    exit $Code
}

# Get-ImpressionConfig: reads KEY=VALUE lines from impression.local.conf without
# executing it. Only known keys are read, and environment variables win over the file.
function Get-ImpressionConfig {
    $config = @{}
    $file = Join-Path $script:ImpressionRoot 'impression.local.conf'
    if (Test-Path -LiteralPath $file) {
        foreach ($line in Get-Content -LiteralPath $file) {
            $line = $line.Trim()
            if ($line -eq '' -or $line.StartsWith('#') -or -not $line.Contains('=')) { continue }
            $key, $value = $line.Split('=', 2)
            $key = $key.Trim()
            $value = $value.Trim()
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if ($key -in 'PCSX2_PATH', 'PCSX2_ARGS') { $config[$key] = $value }
        }
    }
    foreach ($key in 'PCSX2_PATH', 'PCSX2_ARGS') {
        $fromEnv = [Environment]::GetEnvironmentVariable($key)
        if (-not [string]::IsNullOrEmpty($fromEnv)) { $config[$key] = $fromEnv }
    }
    return $config
}

# Resolve-ImpressionProject <path>: returns @{ Abs; Rel } (Rel is relative to the
# repo root, with forward slashes).
function Resolve-ImpressionProject {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { Stop-Script $script:ExitUsage 'missing project path' }
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        Stop-Script $script:ExitUsage "project directory not found: $Path"
    }
    $abs = $resolved.Path.TrimEnd('\')
    $prefix = $script:ImpressionRoot.TrimEnd('\') + '\'
    if (($abs + '\').Equals($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Script $script:ExitUsage 'project must be a subdirectory, not the repository root'
    }
    if (-not ($abs + '\').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Script $script:ExitUsage "project must be inside the repository: $abs"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $abs 'Makefile'))) {
        Stop-Script $script:ExitUsage "no Makefile in project: $abs"
    }
    return @{ Abs = $abs; Rel = $abs.Substring($prefix.Length).Replace('\', '/') }
}

# Find-ImpressionElf <project-abs>: returns the single *.elf in <project>/bin.
function Find-ImpressionElf {
    param([string]$ProjectAbs)
    $found = @(Get-ChildItem -Path (Join-Path $ProjectAbs 'bin') -Filter '*.elf' -File -ErrorAction SilentlyContinue)
    if ($found.Count -lt 1) { Stop-Script $script:ExitUsage "no .elf in $ProjectAbs\bin (build the project first)" }
    if ($found.Count -gt 1) { Stop-Script $script:ExitUsage "more than one .elf in $ProjectAbs\bin: $($found.Name -join ', ')" }
    return $found[0].FullName
}
