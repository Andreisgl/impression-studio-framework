# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Shared helpers for build-project.sh and run-project.sh. Sourced, not executed.
# The contract these scripts expose to tools is documented in docs/tooling-contract.md.

IMPRESSION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

EXIT_FAIL=1   # the build or launch itself failed
EXIT_USAGE=2  # bad arguments, unknown project, missing or ambiguous ELF
EXIT_ENV=3    # environment problem: docker, git or PCSX2 missing or misconfigured

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
    local file="$IMPRESSION_ROOT/impression.local.conf" line key value
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

# resolve_project <path>: sets PROJECT_ABS and PROJECT_REL (relative to the repo root).
resolve_project() {
    [ -n "${1:-}" ] || die "$EXIT_USAGE" "missing project path"
    PROJECT_ABS="$(cd "$1" 2>/dev/null && pwd)" || die "$EXIT_USAGE" "project directory not found: $1"
    case "$PROJECT_ABS/" in
        "$IMPRESSION_ROOT"/*) ;;
        *) die "$EXIT_USAGE" "project must be inside the repository: $PROJECT_ABS" ;;
    esac
    [ "$PROJECT_ABS" != "$IMPRESSION_ROOT" ] || die "$EXIT_USAGE" "project must be a subdirectory, not the repository root"
    [ -f "$PROJECT_ABS/Makefile" ] || die "$EXIT_USAGE" "no Makefile in project: $PROJECT_ABS"
    PROJECT_REL="${PROJECT_ABS#"$IMPRESSION_ROOT"/}"
}

# find_elf: sets ELF to the single *.elf in <project>/bin.
find_elf() {
    local found=()
    shopt -s nullglob
    found=("$PROJECT_ABS"/bin/*.elf)
    shopt -u nullglob
    [ "${#found[@]}" -ge 1 ] || die "$EXIT_USAGE" "no .elf in $PROJECT_ABS/bin (build the project first)"
    [ "${#found[@]}" -eq 1 ] || die "$EXIT_USAGE" "more than one .elf in $PROJECT_ABS/bin: ${found[*]}"
    ELF="${found[0]}"
}
