# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Host launcher for the toolchain container. Usage: scripts\imp.ps1 [-p <project>] <command> [args...]
#   start | stop | restart | status | shell      manage the long-lived container
#   rebuild-image                                rebuild the toolchain image
#   build | clean | make [args]                  act on the project
#   build-engine | clean-engine                  Tyra's engine library
#   build-framework | clean-framework            the framework library
# The container is started automatically when a command needs it. The project is
# -p <folder>, else the PROJECT_DIR environment variable, else project/.
# Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment. docs/tooling-contract.md
# 'Continue': docker writes ordinary messages to stderr (for example "no such
# object" when the container is not created yet), which must not abort the script.
# Exit codes of native commands are checked explicitly.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Select-Toolchain

$rest = @($args)
$projectArg = ''
while ($rest.Count -gt 0) {
    if ($rest[0] -in '-p', '-project', '--project') {
        if ($rest.Count -lt 2) { Stop-Script $script:ExitUsage "$($rest[0]) needs a folder" }
        $projectArg = $rest[1]
        $rest = @($rest | Select-Object -Skip 2)
    } elseif ($rest[0] -in '-h', '-help', '--help') {
        Get-Content $PSCommandPath -TotalCount 12 | Select-Object -Skip 3 | ForEach-Object { $_ -replace '^# ?', '' }
        exit 0
    } else {
        break
    }
}
if ($rest.Count -lt 1) { Stop-Script $script:ExitUsage 'missing command (try: imp.ps1 --help)' }
$command = $rest[0]
$commandArgs = @($rest | Select-Object -Skip 1)

switch ($command) {
    'status' {
        Assert-Docker
        $state = (docker inspect -f '{{.State.Status}}' $script:Container 2>$null)
        if ($LASTEXITCODE -ne 0) { $state = 'not created' }
        Write-Output "$($script:Container): $state"
    }
    'stop' {
        Assert-Docker
        docker stop $script:Container *> $null
        Write-Output "$($script:Container) stopped"
    }
    'rebuild-image' {
        Assert-Docker
        docker rm -f $script:Container *> $null
        docker rmi $script:Image *> $null
        Confirm-Images
    }
    { $_ -in 'start', 'restart', 'shell', 'build', 'clean', 'make', 'build-engine', 'clean-engine', 'build-framework', 'clean-framework' } {
        $projectAbs = Resolve-ImpressionProject $projectArg
        Get-ProjectConfig $projectAbs | Out-Null  # side effect: creates impression.local.conf if missing
        Assert-Docker
        if ($command -eq 'restart') { docker rm -f $script:Container *> $null }
        Confirm-Container $projectAbs
        switch ($command) {
            { $_ -in 'start', 'restart' } { Write-Output "$($script:Container) running (project: $projectAbs)" }
            'shell' { docker exec -it -w /project $script:Container bash }
            default {
                Invoke-ContainerImp $command @commandArgs
                exit $LASTEXITCODE
            }
        }
    }
    default { Stop-Script $script:ExitUsage "unknown command: $command" }
}
