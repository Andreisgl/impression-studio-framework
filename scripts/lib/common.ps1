# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Shared helpers for the host launchers (imp.ps1, build-project.ps1, run-project.ps1,
# make.ps1). Dot-sourced, not executed. The contract these scripts expose to tools
# is documented in docs/tooling-contract.md.

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

# Toolchain flavour. The default is the current official ps2dev image (GCC 15, openvcl;
# docker/Dockerfile.modern), which the ported Tyra fork needs. IMPRESSION_TOOLCHAIN=snapshot
# selects the source-built July 2022 snapshot (docker/Dockerfile.ps2dev), which only builds
# the unported Tyra (upstream master). Each flavour has its own container.
$script:ImageBase = ''
$script:Image = 'impression/toolchain:modern'
$script:Container = 'impression-dev'
$script:ImageDockerfile = 'docker\Dockerfile.modern'
$script:ImageContext = 'docker'

# Select-Toolchain: applies IMPRESSION_TOOLCHAIN. Every entry script calls it right
# after dot-sourcing this file: an `exit` executed while a file is being dot-sourced
# does not stop the calling script, so the check has to run from the caller's scope.
function Select-Toolchain {
    $flavour = $env:IMPRESSION_TOOLCHAIN
    if ([string]::IsNullOrEmpty($flavour)) { $flavour = 'modern' }
    if ($flavour -eq 'snapshot') {
        $script:ImageBase = 'impression/ps2dev:2022-07'
        $script:Image = 'impression/toolchain:dev'
        $script:Container = 'impression-dev-snapshot'
        $script:ImageDockerfile = 'docker\Dockerfile'
        $script:ImageContext = 'extern\tyra\assets'
    } elseif ($flavour -ne 'modern') {
        Stop-Script $script:ExitUsage "IMPRESSION_TOOLCHAIN must be 'modern' or 'snapshot' (got '$flavour')"
    }
}

# Get-ImpressionConfig: reads KEY=VALUE lines from impression.local.conf without
# executing it. Only known keys are read, and environment variables win over the file.
function Get-ImpressionConfig {
    $keys = 'PCSX2_PATH', 'PCSX2_ARGS', 'PROJECT_DIR'
    $config = @{}
    $file = Join-Path $script:ImpressionRoot 'impression.local.conf'
    $example = Join-Path $script:ImpressionRoot 'impression.local.conf.example'
    if (-not (Test-Path -LiteralPath $file) -and (Test-Path -LiteralPath $example)) {
        Copy-Item -LiteralPath $example -Destination $file
        [Console]::Error.WriteLine('Created impression.local.conf (from impression.local.conf.example). Edit it to set PCSX2_PATH before running a project.')
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

# Resolve-ImpressionProject <path> <config>: returns the absolute project folder. A
# path given as an argument is relative to the current directory; PROJECT_DIR from
# the config is relative to the repo root; with neither, the framework's own
# project/ folder is used. Any folder on the host works: the container mounts it
# at /project.
function Resolve-ImpressionProject {
    param([string]$Path, [hashtable]$Config)
    if (-not [string]::IsNullOrEmpty($Path)) {
        $base = (Get-Location).Path
    } else {
        $Path = $Config['PROJECT_DIR']
        if ([string]::IsNullOrEmpty($Path)) { $Path = 'project' }
        $base = $script:ImpressionRoot
    }
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $base $Path }
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        Stop-Script $script:ExitUsage "project directory not found: $Path"
    }
    $abs = $resolved.Path.TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $abs 'Makefile'))) {
        Stop-Script $script:ExitUsage "no Makefile in project folder: $abs"
    }
    return $abs
}

function Assert-Docker {
    $ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Stop-Script $script:ExitEnv 'docker not found in PATH' }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { Stop-Script $script:ExitEnv 'the docker daemon is not reachable (is Docker running?)' }
}

function Test-DockerImage {
    param([string]$Name)
    $ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked
    docker image inspect $Name *> $null
    return ($LASTEXITCODE -eq 0)
}

# Checks the Tyra submodule out when it is missing. An existing checkout is left alone:
# `submodule update` would reset a fork branch you are working on (or fail on
# uncommitted changes).
function Update-Submodules {
    $ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked
    if (Test-Path -LiteralPath (Join-Path $script:ImpressionRoot 'extern\tyra\Makefile.base')) { return }
    git -C $script:ImpressionRoot submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { Stop-Script $script:ExitEnv 'git submodule update failed' }
}

# Confirm-Images: builds the toolchain images when missing. The first one is a
# one-time build from source and takes a long time; its progress is printed.
function Confirm-Images {
    $ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked
    if ($script:ImageBase -and -not (Test-DockerImage $script:ImageBase)) {
        [Console]::Error.WriteLine('Building the PS2DEV toolchain image (one time, this takes a long while)...')
        docker build -f (Join-Path $script:ImpressionRoot 'docker\Dockerfile.ps2dev') -t $script:ImageBase (Join-Path $script:ImpressionRoot 'docker')
        if ($LASTEXITCODE -ne 0) { Stop-Script $script:ExitEnv "building $($script:ImageBase) failed" }
    }
    if (-not (Test-DockerImage $script:Image)) {
        Update-Submodules
        $context = Join-Path $script:ImpressionRoot $script:ImageContext
        if ($script:ImageBase -and -not (Test-Path -LiteralPath (Join-Path $context 'vcl'))) { Stop-Script $script:ExitEnv "$($script:ImageContext)/vcl is missing (submodule not checked out)" }
        [Console]::Error.WriteLine("Building the toolchain image $($script:Image)...")
        docker build -f (Join-Path $script:ImpressionRoot $script:ImageDockerfile) -t $script:Image $context
        if ($LASTEXITCODE -ne 0) { Stop-Script $script:ExitEnv "building $($script:Image) failed" }
    }
}

# Confirm-Container <project-abs>: makes sure the long-lived container is running
# with the right mounts. A container whose mounts or image no longer match (another
# project was chosen, the image was rebuilt) is recreated.
function Confirm-Container {
    param([string]$ProjectAbs)
    $ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked
    Assert-Docker
    Confirm-Images
    Update-Submodules

    $imageId = (docker image inspect -f '{{.Id}}' $script:Image)
    $signature = "$($script:ImpressionRoot)|$ProjectAbs|$imageId"

    # Windows PowerShell 5.1 drops double quotes inside native arguments, so the label
    # is read as JSON instead of with a quoted Go template.
    $current = ''
    $labelsJson = (docker inspect -f '{{json .Config.Labels}}' $script:Container 2>$null)
    if ($LASTEXITCODE -eq 0 -and $labelsJson) {
        $labels = $labelsJson | ConvertFrom-Json
        if ($labels.PSObject.Properties.Name -contains 'impression.signature') { $current = $labels.'impression.signature' }
    }
    if (-not [string]::IsNullOrEmpty($current) -and $current -ne $signature) {
        [Console]::Error.WriteLine("Recreating $($script:Container) (project or image changed)...")
        docker rm -f $script:Container *> $null
        $current = ''
    }

    if ([string]::IsNullOrEmpty($current)) {
        docker run -d --name $script:Container --label "impression.signature=$signature" `
            -e IMPRESSION_HOME=/work `
            -v "$($script:ImpressionRoot):/work" -v "${ProjectAbs}:/project" -w /project `
            $script:Image *> $null
        if ($LASTEXITCODE -ne 0) { Stop-Script $script:ExitEnv "could not create the container $($script:Container)" }
        return
    }

    $running = (docker inspect -f '{{.State.Running}}' $script:Container)
    if ($running -ne 'true') {
        docker start $script:Container *> $null
        if ($LASTEXITCODE -ne 0) { Stop-Script $script:ExitEnv "could not start the container $($script:Container)" }
    }
}

# Invoke-ContainerImp <imp args...>: runs docker/imp inside the container. The exit
# code is imp's own (0 ok, 1 build failed, 2 usage, 3 environment), in $LASTEXITCODE.
function Invoke-ContainerImp {
    $ErrorActionPreference = 'Continue'  # native stderr must not abort; exit codes are checked
    docker exec -w /project $script:Container bash /work/docker/imp @args
}

# Find-ImpressionElf <project-abs>: returns the single *.elf in <project>/bin.
function Find-ImpressionElf {
    param([string]$ProjectAbs)
    $found = @(Get-ChildItem -Path (Join-Path $ProjectAbs 'bin') -Filter '*.elf' -File -ErrorAction SilentlyContinue)
    if ($found.Count -lt 1) { Stop-Script $script:ExitUsage "no .elf in $ProjectAbs\bin (build the project first)" }
    if ($found.Count -gt 1) { Stop-Script $script:ExitUsage "more than one .elf in $ProjectAbs\bin: $($found.Name -join ', ')" }
    return $found[0].FullName
}
