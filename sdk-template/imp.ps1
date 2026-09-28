# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Standalone launcher for the Impression Studio SDK image. Copy this whole folder's
# contents into your own game repo (nothing else needed: the framework and Tyra are
# baked into the published image). Usage: imp.ps1 <command> [args...]
#   build              build the project (this folder, unless -p is given)
#   run [-Build] [-Restart] [-Wait] [-DryRun]   run the ELF in PCSX2 (host)
#   clean              clean the project's own build output
#   shell              open a shell in the toolchain container
#   pull               pull the latest SDK image
#   status             show whether the container is running
#   sync-ide           (re)generate .vscode/c_cpp_properties.json so IntelliSense
#                      resolves <tyra> and <impression/...>; re-run after an
#                      image update
# The project is -p <folder>, else the current directory. Exit codes: 0 ok,
# 1 build/launch failed, 2 usage, 3 environment (docker, or no PCSX2_PATH to run).
$ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked

# ---- configuration: change $Image (or set IMPRESSION_SDK_IMAGE) to pin a version --
$Image = $env:IMPRESSION_SDK_IMAGE
if ([string]::IsNullOrEmpty($Image)) { $Image = 'andreisgl/impression-studio-sdk:latest' }
# ------------------------------------------------------------------------------------

$Here = $PSScriptRoot
$ExitFail = 1
$ExitUsage = 2
$ExitEnv = 3

function Stop-Script {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("error: $Message")
    exit $Code
}

function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Stop-Script $ExitEnv 'docker not found in PATH' }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { Stop-Script $ExitEnv 'the docker daemon is not reachable (is Docker running?)' }
}

function Get-ProjectHash {
    param([string]$ProjectAbs)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ProjectAbs))
    } finally {
        $md5.Dispose()
    }
    return ([System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant().Substring(0, 12))
}

function Resolve-ImpressionProject {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { $Path = (Get-Location).Path }
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        Stop-Script $ExitUsage "project directory not found: $Path"
    }
    $abs = $resolved.Path.TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $abs 'Makefile'))) {
        Stop-Script $ExitUsage "no Makefile in project folder: $abs"
    }
    return $abs
}

# Get-ProjectConfig <project-abs>: reads KEY=VALUE lines from
# <project>/impression.local.conf (created from impression.local.conf.example if
# missing) without executing it. Environment variables win over the file.
function Get-ProjectConfig {
    param([string]$ProjectAbs)
    $keys = 'PCSX2_PATH', 'PCSX2_ARGS'
    $config = @{}
    $file = Join-Path $ProjectAbs 'impression.local.conf'
    $example = Join-Path $Here 'impression.local.conf.example'
    if (-not (Test-Path -LiteralPath $file) -and (Test-Path -LiteralPath $example)) {
        Copy-Item -LiteralPath $example -Destination $file
        [Console]::Error.WriteLine("Created $file (from impression.local.conf.example). Edit it to set PCSX2_PATH before running.")
    }
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
            if ($key -in $keys) { $config[$key] = $value }
        }
    }
    foreach ($key in $keys) {
        $fromEnv = [Environment]::GetEnvironmentVariable($key)
        if (-not [string]::IsNullOrEmpty($fromEnv)) { $config[$key] = $fromEnv }
    }
    return $config
}

function Confirm-Container {
    param([string]$ProjectAbs)
    Assert-Docker
    $script:Container = "impression-sdk-$(Get-ProjectHash $ProjectAbs)"

    if (-not (docker image inspect $Image 2>$null) -or $LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("Pulling $Image (one time; cached by Docker after this)...")
        docker pull $Image
        if ($LASTEXITCODE -ne 0) { Stop-Script $ExitEnv "pulling $Image failed" }
    }

    $imageId = (docker image inspect -f '{{.Id}}' $Image)
    $signature = "$ProjectAbs|$imageId"

    $current = ''
    $labelsJson = (docker inspect -f '{{json .Config.Labels}}' $script:Container 2>$null)
    if ($LASTEXITCODE -eq 0 -and $labelsJson) {
        $labels = $labelsJson | ConvertFrom-Json
        if ($labels.PSObject.Properties.Name -contains 'impression.signature') { $current = $labels.'impression.signature' }
    }
    if (-not [string]::IsNullOrEmpty($current) -and $current -ne $signature) {
        [Console]::Error.WriteLine("Recreating $($script:Container) (image updated)...")
        docker rm -f $script:Container *> $null
        $current = ''
    }

    if ([string]::IsNullOrEmpty($current)) {
        docker run -d --name $script:Container --label "impression.signature=$signature" `
            -v "${ProjectAbs}:/project" -w /project `
            $Image *> $null
        if ($LASTEXITCODE -ne 0) { Stop-Script $ExitEnv "could not create the container $($script:Container)" }
        return
    }

    $running = (docker inspect -f '{{.State.Running}}' $script:Container)
    if ($running -ne 'true') {
        docker start $script:Container *> $null
        if ($LASTEXITCODE -ne 0) { Stop-Script $ExitEnv "could not start the container $($script:Container)" }
    }
}

function Invoke-ContainerImp {
    docker exec -w /project $script:Container bash -c 'bash "$IMPRESSION_HOME/docker/imp" "$@"' bash @args
}

function Find-ImpressionElf {
    param([string]$ProjectAbs)
    $found = @(Get-ChildItem -Path (Join-Path $ProjectAbs 'bin') -Filter '*.elf' -File -ErrorAction SilentlyContinue)
    if ($found.Count -lt 1) { Stop-Script $ExitUsage "no .elf in $ProjectAbs\bin (build the project first)" }
    if ($found.Count -gt 1) { Stop-Script $ExitUsage "more than one .elf in $ProjectAbs\bin: $($found.Name -join ', ')" }
    return $found[0].FullName
}

function Invoke-Build {
    param([string]$Project)
    $projectAbs = Resolve-ImpressionProject $Project
    Get-ProjectConfig $projectAbs | Out-Null  # side effect: creates impression.local.conf if missing
    Confirm-Container $projectAbs
    Invoke-ContainerImp build | ForEach-Object {
        if ($_ -match '^IMPRESSION_ELF=(.+)$') { "IMPRESSION_ELF=$projectAbs\" + ($Matches[1] -replace '/', '\') } else { $_ }
    }
    if ($LASTEXITCODE -ne 0) { Stop-Script $ExitFail "build failed (exit code $LASTEXITCODE)" }
    return $projectAbs
}

function Invoke-Run {
    param([string[]]$RunArgs)
    $project = ''
    $build = $false; $restart = $false; $wait = $false; $dryRun = $false
    foreach ($a in $RunArgs) {
        switch ($a) {
            '--build' { $build = $true }
            '--restart' { $restart = $true }
            '--wait' { $wait = $true }
            '--dry-run' { $dryRun = $true }
            default {
                if ($a.StartsWith('-')) { Stop-Script $ExitUsage "unknown option: $a" }
                if ($project -ne '') { Stop-Script $ExitUsage 'only one project path is allowed' }
                $project = $a
            }
        }
    }

    $projectAbs = Resolve-ImpressionProject $project
    $config = Get-ProjectConfig $projectAbs
    $pcsx2Path = $config['PCSX2_PATH']
    if ([string]::IsNullOrEmpty($pcsx2Path)) {
        Stop-Script $ExitEnv "PCSX2_PATH is not set in $projectAbs\impression.local.conf. Edit that file and set it."
    }

    if ($build) { Invoke-Build $projectAbs | Out-Null }
    $elf = Find-ImpressionElf $projectAbs

    $emu = $null
    if (Test-Path -LiteralPath $pcsx2Path -PathType Leaf) {
        $emu = (Resolve-Path -LiteralPath $pcsx2Path).Path
    } elseif (Test-Path -LiteralPath $pcsx2Path -PathType Container) {
        foreach ($name in 'pcsx2-qt.exe', 'pcsx2-qtx64.exe', 'pcsx2-qtx64-avx2.exe', 'pcsx2x64.exe', 'pcsx2.exe') {
            $candidate = Join-Path $pcsx2Path $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $emu = (Resolve-Path -LiteralPath $candidate).Path; break }
        }
    }
    if (-not $emu) { Stop-Script $ExitEnv "PCSX2 executable not found at PCSX2_PATH=$pcsx2Path" }

    $emuDir = Split-Path $emu -Parent
    $emuName = [IO.Path]::GetFileNameWithoutExtension($emu)
    $isLegacy = ($emuName -in 'pcsx2', 'pcsx2x64') -and -not (Test-Path -LiteralPath (Join-Path $emuDir 'qt.conf'))
    $argList = @()
    if (-not [string]::IsNullOrWhiteSpace($config['PCSX2_ARGS'])) {
        $argList += $config['PCSX2_ARGS'].Trim() -split '\s+'
    }
    if ($isLegacy) { $argList += "--elf=`"$elf`"" } else { $argList += '-elf', "`"$elf`"" }

    if ($dryRun) {
        Write-Output "IMPRESSION_CMD=`"$emu`" $($argList -join ' ')"
        return
    }

    Remove-Item -LiteralPath (Join-Path $projectAbs 'bin\log.txt') -Force -ErrorAction SilentlyContinue

    if ($restart) {
        Get-Process -Name $emuName -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 800
    }

    if ($wait) {
        Start-Process -FilePath $emu -ArgumentList $argList -Wait
        return
    }

    $process = Start-Process -FilePath $emu -ArgumentList $argList -PassThru
    Write-Output "IMPRESSION_PID=$($process.Id)"
}

$rest = @($args)
$projectArg = ''
while ($rest.Count -gt 0) {
    if ($rest[0] -in '-p', '-project', '--project') {
        if ($rest.Count -lt 2) { Stop-Script $ExitUsage "$($rest[0]) needs a folder" }
        $projectArg = $rest[1]
        $rest = @($rest | Select-Object -Skip 2)
    } elseif ($rest[0] -in '-h', '-help', '--help') {
        Get-Content $PSCommandPath -TotalCount 17 | Select-Object -Skip 3 | ForEach-Object { $_ -replace '^# ?', '' }
        exit 0
    } else {
        break
    }
}
if ($rest.Count -lt 1) { Stop-Script $ExitUsage 'missing command (try: imp.ps1 --help)' }
$command = $rest[0]
$commandArgs = @($rest | Select-Object -Skip 1)

switch ($command) {
    'build' { Invoke-Build $projectArg | Out-Null }
    'run' { Invoke-Run $commandArgs }
    'clean' {
        $projectAbs = Resolve-ImpressionProject $projectArg
        Confirm-Container $projectAbs
        Invoke-ContainerImp clean
    }
    'shell' {
        $projectAbs = Resolve-ImpressionProject $projectArg
        Confirm-Container $projectAbs
        docker exec -it -w /project $script:Container bash
    }
    'sync-ide' {
        $projectAbs = Resolve-ImpressionProject $projectArg
        Confirm-Container $projectAbs
        Invoke-ContainerImp sync-ide
    }
    'pull' {
        Assert-Docker
        docker pull $Image
    }
    'status' {
        $projectAbs = Resolve-ImpressionProject $projectArg
        Assert-Docker
        $container = "impression-sdk-$(Get-ProjectHash $projectAbs)"
        $state = (docker inspect -f '{{.State.Status}}' $container 2>$null)
        if ($LASTEXITCODE -ne 0) { $state = 'not created' }
        Write-Output "${container}: $state"
    }
    default { Stop-Script $ExitUsage "unknown command: $command (try: imp.ps1 --help)" }
}
exit $LASTEXITCODE
