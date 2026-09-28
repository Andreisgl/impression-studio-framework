#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Standalone launcher for the Impression Studio SDK image. Copy this whole folder's
# contents into your own game repo (nothing else needed: the framework and Tyra are
# baked into the published image). Usage: imp.sh <command> [args...]
#   build              build the project (this folder, unless -p is given)
#   run [--build] [--restart] [--wait] [--dry-run]   run the ELF in PCSX2 (host)
#   clean              clean the project's own build output
#   shell              open a shell in the toolchain container
#   pull               pull the latest SDK image
#   status             show whether the container is running
# The project is -p <folder>, else the current directory. Exit codes: 0 ok,
# 1 build/launch failed, 2 usage, 3 environment (docker, or no PCSX2_PATH to run).
set -euo pipefail

# ---- configuration: change IMAGE to pin a specific version -----------------
IMAGE="${IMPRESSION_SDK_IMAGE:-andreisgl/impression-studio-sdk:latest}"
# ------------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXIT_FAIL=1
EXIT_USAGE=2
EXIT_ENV=3

# Git Bash on Windows would otherwise rewrite container paths passed to docker.
export MSYS_NO_PATHCONV=1

die() {
    local code=$1
    shift
    echo "error: $*" >&2
    exit "$code"
}

# to_native_path <path>: converts a host path for use as an argument to a native
# program (docker, PCSX2). Git Bash's own paths are POSIX-style and not everything
# understands them (see the framework repo's scripts/lib/common.sh for the story);
# a no-op where there is no cygpath (Linux, macOS).
to_native_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

need_docker() {
    command -v docker >/dev/null 2>&1 || die "$EXIT_ENV" "docker not found in PATH"
    docker info >/dev/null 2>&1 || die "$EXIT_ENV" "the docker daemon is not reachable (is Docker running?)"
}

# project_hash: a short, stable identifier for PROJECT_ABS, so more than one
# project on the same machine gets its own container.
project_hash() {
    if command -v sha1sum >/dev/null 2>&1; then
        printf '%s' "$PROJECT_ABS" | sha1sum | cut -c1-12
    else
        printf '%s' "$PROJECT_ABS" | shasum -a 1 | cut -c1-12
    fi
}

resolve_project() {
    local path="${1:-$PWD}"
    PROJECT_ABS="$(cd "$path" 2>/dev/null && pwd)" || die "$EXIT_USAGE" "project directory not found: $path"
    [ -f "$PROJECT_ABS/Makefile" ] || die "$EXIT_USAGE" "no Makefile in project folder: $PROJECT_ABS"
}

# load_project_config: reads KEY=VALUE lines from <project>/impression.local.conf
# (created from impression.local.conf.example if missing), without executing it.
load_project_config() {
    local file="$PROJECT_ABS/impression.local.conf"
    local example="$HERE/impression.local.conf.example"
    local line key value
    if [ ! -f "$file" ] && [ -f "$example" ]; then
        cp "$example" "$file"
        echo "Created $file (from impression.local.conf.example). Edit it to set PCSX2_PATH before running." >&2
    fi
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in '' | '#'*) continue ;; esac
        case "$line" in *=*) ;; *) continue ;; esac
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        case "$key" in PCSX2_PATH | PCSX2_ARGS) ;; *) continue ;; esac
        if [ -z "${!key:-}" ]; then export "$key=$value"; fi
    done <"$file"
}

ensure_container() {
    need_docker
    CONTAINER="impression-sdk-$(project_hash)"
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "Pulling $IMAGE (one time; cached by Docker after this)..." >&2
        docker pull "$IMAGE" >&2 || die "$EXIT_ENV" "pulling $IMAGE failed"
    fi

    local image_id signature current running
    image_id="$(docker image inspect -f '{{.Id}}' "$IMAGE")"
    signature="$PROJECT_ABS|$image_id"
    current="$(docker inspect -f '{{index .Config.Labels "impression.signature"}}' "$CONTAINER" 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "$signature" ]; then
        echo "Recreating $CONTAINER (image updated)..." >&2
        docker rm -f "$CONTAINER" >/dev/null
        current=""
    fi

    if [ -z "$current" ]; then
        local user_args=()
        if [ "$(uname -s)" = "Linux" ]; then user_args=(--user "$(id -u):$(id -g)"); fi
        docker run -d --name "$CONTAINER" --label "impression.signature=$signature" \
            ${user_args[@]+"${user_args[@]}"} \
            -v "$(to_native_path "$PROJECT_ABS"):/project" -w /project \
            "$IMAGE" >/dev/null || die "$EXIT_ENV" "could not create the container $CONTAINER"
        return 0
    fi

    running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER")"
    if [ "$running" != "true" ]; then
        docker start "$CONTAINER" >/dev/null || die "$EXIT_ENV" "could not start the container $CONTAINER"
    fi
}

container_imp() {
    docker exec -w /project "$CONTAINER" bash -c 'bash "$IMPRESSION_HOME/docker/imp" "$@"' bash "$@"
}

find_elf() {
    local found=()
    shopt -s nullglob
    found=("$PROJECT_ABS"/bin/*.elf)
    shopt -u nullglob
    [ "${#found[@]}" -ge 1 ] || die "$EXIT_USAGE" "no .elf in $PROJECT_ABS/bin (build the project first)"
    [ "${#found[@]}" -eq 1 ] || die "$EXIT_USAGE" "more than one .elf in $PROJECT_ABS/bin: ${found[*]}"
    ELF="${found[0]}"
}

cmd_build() {
    resolve_project "$1"
    load_project_config
    ensure_container
    local project_native status rel
    project_native="$(to_native_path "$PROJECT_ABS")"
    status=0
    container_imp build | while IFS= read -r line; do
        case "$line" in
            IMPRESSION_ELF=*)
                rel="${line#IMPRESSION_ELF=}"
                echo "IMPRESSION_ELF=${project_native}\\${rel//\//\\}"
                ;;
            *) echo "$line" ;;
        esac
    done || status=$?
    [ "$status" -eq 0 ] || die "$EXIT_FAIL" "build failed (exit code $status)"
}

cmd_run() {
    local project="" build=0 restart=0 wait_exit=0 dry_run=0
    for arg in "$@"; do
        case "$arg" in
            --build) build=1 ;;
            --restart) restart=1 ;;
            --wait) wait_exit=1 ;;
            --dry-run) dry_run=1 ;;
            -*) die "$EXIT_USAGE" "unknown option: $arg" ;;
            *)
                [ -z "$project" ] || die "$EXIT_USAGE" "only one project path is allowed"
                project="$arg"
                ;;
        esac
    done

    resolve_project "$project"
    load_project_config
    [ -n "${PCSX2_PATH:-}" ] || die "$EXIT_ENV" "PCSX2_PATH is not set in $PROJECT_ABS/impression.local.conf. Edit that file and set it."

    if [ "$build" -eq 1 ]; then
        cmd_build "$PROJECT_ABS"
    fi
    find_elf
    ELF="$(to_native_path "$ELF")"

    local emu=""
    if [ -f "$PCSX2_PATH" ]; then
        emu="$PCSX2_PATH"
    elif [ -d "$PCSX2_PATH" ]; then
        local name
        for name in pcsx2-qt pcsx2 PCSX2; do
            if [ -f "$PCSX2_PATH/$name" ] && [ -x "$PCSX2_PATH/$name" ]; then
                emu="$PCSX2_PATH/$name"
                break
            fi
        done
    fi
    [ -n "$emu" ] || die "$EXIT_ENV" "PCSX2 executable not found at PCSX2_PATH=$PCSX2_PATH"

    # Old wx-based builds take --elf=<file>; the Qt builds take -elf <file>.
    local emu_name elf_args=() extra_args=() cmd
    emu_name="$(basename "$emu" | tr '[:upper:]' '[:lower:]')"
    if { [ "$emu_name" = "pcsx2" ] || [ "$emu_name" = "pcsx2x64" ]; } && [ ! -f "$(dirname "$emu")/qt.conf" ]; then
        elf_args=("--elf=$ELF")
    else
        elf_args=(-elf "$ELF")
    fi
    if [ -n "${PCSX2_ARGS:-}" ]; then
        read -r -a extra_args <<<"$PCSX2_ARGS"
    fi
    cmd=("$emu")
    [ "${#extra_args[@]}" -eq 0 ] || cmd+=("${extra_args[@]}")
    cmd+=("${elf_args[@]}")

    if [ "$dry_run" -eq 1 ]; then
        printf 'IMPRESSION_CMD='
        printf '%q ' "${cmd[@]}"
        echo
        return 0
    fi

    # Tyra appends to bin/log.txt across runs; start each run with a fresh log.
    rm -f "$PROJECT_ABS/bin/log.txt"

    if [ "$restart" -eq 1 ]; then
        pkill -f -- "$emu" 2>/dev/null || true
        sleep 1
    fi

    if [ "$wait_exit" -eq 1 ]; then
        "${cmd[@]}" || true
        return 0
    fi

    nohup "${cmd[@]}" >/dev/null 2>&1 &
    local pid=$!
    disown "$pid" 2>/dev/null || true
    echo "IMPRESSION_PID=$pid"
}

project_arg=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p | --project)
            [ "$#" -ge 2 ] || die "$EXIT_USAGE" "$1 needs a folder"
            project_arg="$2"
            shift 2
            ;;
        -h | --help)
            sed -n '5,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) break ;;
    esac
done
[ "$#" -ge 1 ] || die "$EXIT_USAGE" "missing command (try: imp.sh --help)"
command=$1
shift

case "$command" in
    build) cmd_build "$project_arg" ;;
    run) cmd_run "$project_arg" "$@" ;;
    clean)
        resolve_project "$project_arg"
        ensure_container
        container_imp clean
        ;;
    shell)
        resolve_project "$project_arg"
        ensure_container
        docker exec -it -w /project "$CONTAINER" bash
        ;;
    pull)
        need_docker
        docker pull "$IMAGE"
        ;;
    status)
        resolve_project "$project_arg"
        need_docker
        CONTAINER="impression-sdk-$(project_hash)"
        state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not created")"
        echo "$CONTAINER: $state"
        ;;
    *)
        die "$EXIT_USAGE" "unknown command: $command (try: imp.sh --help)"
        ;;
esac
