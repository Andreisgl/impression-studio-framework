# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Shared helpers for the host launchers (imp.sh, build-project.sh, run-project.sh,
# make.sh). Sourced, not executed. The contract these scripts expose to tools is
# documented in docs/tooling-contract.md.

IMPRESSION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

EXIT_FAIL=1   # the build or launch itself failed
EXIT_USAGE=2  # bad arguments, unknown project, missing or ambiguous ELF
EXIT_ENV=3    # environment problem: docker, git or PCSX2 missing or misconfigured

# Git Bash on Windows would otherwise rewrite container paths passed to docker.
export MSYS_NO_PATHCONV=1

# Toolchain flavour. The default is the current official ps2dev image (GCC 15, openvcl;
# docker/Dockerfile.modern), which the ported Tyra fork needs. IMPRESSION_TOOLCHAIN=snapshot
# selects the source-built July 2022 snapshot (docker/Dockerfile.ps2dev), which only builds
# the unported Tyra (upstream master). Each flavour has its own container.
IMAGE_BASE=""
IMAGE="impression/toolchain:modern"
CONTAINER="impression-dev"
IMAGE_DOCKERFILE="docker/Dockerfile.modern"
IMAGE_CONTEXT="docker"
case "${IMPRESSION_TOOLCHAIN:-modern}" in
    modern) ;;
    snapshot)
        IMAGE_BASE="impression/ps2dev:2022-07"
        IMAGE="impression/toolchain:dev"
        CONTAINER="impression-dev-snapshot"
        IMAGE_DOCKERFILE="docker/Dockerfile"
        IMAGE_CONTEXT="extern/tyra/assets"
        ;;
    *)
        echo "error: IMPRESSION_TOOLCHAIN must be 'modern' or 'snapshot' (got '${IMPRESSION_TOOLCHAIN}')" >&2
        exit "$EXIT_USAGE"
        ;;
esac

# die <exit-code> <message...>: message to stderr, then exit.
die() {
    local code=$1
    shift
    echo "error: $*" >&2
    exit "$code"
}

# load_config: reads KEY=VALUE lines from impression.local.conf without executing
# it. Only known keys are read, and variables already set in the environment win,
# so a tool can override the file per invocation.
load_config() {
    local file="$IMPRESSION_ROOT/impression.local.conf"
    local example="$IMPRESSION_ROOT/impression.local.conf.example"
    local line key value
    if [ ! -f "$file" ] && [ -f "$example" ]; then
        cp "$example" "$file"
        echo "Created impression.local.conf (from impression.local.conf.example). Edit it to set PCSX2_PATH before running a project." >&2
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
        case "$key" in PCSX2_PATH | PCSX2_ARGS | PROJECT_DIR) ;; *) continue ;; esac
        if [ -z "${!key:-}" ]; then export "$key=$value"; fi
    done <"$file"
}

# resolve_project [path]: sets PROJECT_ABS. A path given as an argument is relative
# to the current directory; PROJECT_DIR from the config is relative to the repo
# root; with neither, the framework's own project/ folder is used. Any folder on
# the host works: the container mounts it at /project.
resolve_project() {
    local path="${1:-}" base
    if [ -n "$path" ]; then
        base="$PWD"
    else
        path="${PROJECT_DIR:-project}"
        base="$IMPRESSION_ROOT"
    fi
    case "$path" in
        /* | [A-Za-z]:*) ;;
        *) path="$base/$path" ;;
    esac
    PROJECT_ABS="$(cd "$path" 2>/dev/null && pwd)" || die "$EXIT_USAGE" "project directory not found: $path"
    [ -f "$PROJECT_ABS/Makefile" ] || die "$EXIT_USAGE" "no Makefile in project folder: $PROJECT_ABS"
}

need_docker() {
    command -v docker >/dev/null 2>&1 || die "$EXIT_ENV" "docker not found in PATH"
    docker info >/dev/null 2>&1 || die "$EXIT_ENV" "the docker daemon is not reachable (is Docker running?)"
}

# ensure_images: builds the toolchain images when missing. The first one is a
# one-time build from source and takes a long time; progress goes to stderr so
# stdout stays clean for tools.
ensure_images() {
    if [ -n "$IMAGE_BASE" ] && ! docker image inspect "$IMAGE_BASE" >/dev/null 2>&1; then
        echo "Building the PS2DEV toolchain image (one time, this takes a long while)..." >&2
        docker build -f "$IMPRESSION_ROOT/docker/Dockerfile.ps2dev" -t "$IMAGE_BASE" "$IMPRESSION_ROOT/docker" >&2 ||
            die "$EXIT_ENV" "building $IMAGE_BASE failed"
    fi
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        update_submodules
        if [ -z "$IMAGE_BASE" ] || [ -f "$IMPRESSION_ROOT/$IMAGE_CONTEXT/vcl" ]; then :; else
            die "$EXIT_ENV" "$IMAGE_CONTEXT/vcl is missing (submodule not checked out)"
        fi
        echo "Building the toolchain image $IMAGE..." >&2
        docker build -f "$IMPRESSION_ROOT/$IMAGE_DOCKERFILE" -t "$IMAGE" "$IMPRESSION_ROOT/$IMAGE_CONTEXT" >&2 ||
            die "$EXIT_ENV" "building $IMAGE failed"
    fi
}

# update_submodules: checks the Tyra submodule out when it is missing. An existing
# checkout is left alone: `submodule update` would reset a fork branch you are
# working on (or fail on uncommitted changes).
update_submodules() {
    [ -f "$IMPRESSION_ROOT/extern/tyra/Makefile.base" ] && return 0
    git -C "$IMPRESSION_ROOT" submodule update --init --recursive >&2 || die "$EXIT_ENV" "git submodule update failed"
}

# ensure_container: makes sure the long-lived container is running with the right
# mounts. A container whose mounts or image no longer match (another project was
# chosen, the image was rebuilt) is recreated. Needs PROJECT_ABS.
ensure_container() {
    need_docker
    ensure_images
    update_submodules

    local image_id signature current running
    image_id="$(docker image inspect -f '{{.Id}}' "$IMAGE")"
    signature="$IMPRESSION_ROOT|$PROJECT_ABS|$image_id"

    current="$(docker inspect -f '{{index .Config.Labels "impression.signature"}}' "$CONTAINER" 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "$signature" ]; then
        echo "Recreating $CONTAINER (project or image changed)..." >&2
        docker rm -f "$CONTAINER" >/dev/null
        current=""
    fi

    if [ -z "$current" ]; then
        local user_args=()
        # On Linux, files created in the mounts should belong to the caller.
        if [ "$(uname -s)" = "Linux" ]; then user_args=(--user "$(id -u):$(id -g)"); fi
        docker run -d --name "$CONTAINER" --label "impression.signature=$signature" \
            ${user_args[@]+"${user_args[@]}"} -e IMPRESSION_HOME=/work \
            -v "$IMPRESSION_ROOT:/work" -v "$PROJECT_ABS:/project" -w /project \
            "$IMAGE" >/dev/null || die "$EXIT_ENV" "could not create the container $CONTAINER"
        return 0
    fi

    running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER")"
    if [ "$running" != "true" ]; then
        docker start "$CONTAINER" >/dev/null || die "$EXIT_ENV" "could not start the container $CONTAINER"
    fi
}

# container_imp <imp args...>: runs docker/imp inside the container. The exit code
# is imp's own (0 ok, 1 build failed, 2 usage, 3 environment).
container_imp() {
    docker exec -w /project "$CONTAINER" bash /work/docker/imp "$@"
}

# find_elf: sets ELF to the single *.elf in <project>/bin on the host.
find_elf() {
    local found=()
    shopt -s nullglob
    found=("$PROJECT_ABS"/bin/*.elf)
    shopt -u nullglob
    [ "${#found[@]}" -ge 1 ] || die "$EXIT_USAGE" "no .elf in $PROJECT_ABS/bin (build the project first)"
    [ "${#found[@]}" -eq 1 ] || die "$EXIT_USAGE" "more than one .elf in $PROJECT_ABS/bin: ${found[*]}"
    ELF="${found[0]}"
}
