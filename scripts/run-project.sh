#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Runs a project's ELF in PCSX2. The emulator location comes from PCSX2_PATH in
# impression.local.conf (or the environment). Does not build unless asked.
# Usage: scripts/run-project.sh <project-dir> [--build] [--restart] [--wait] [--dry-run]
#   --build    build the project first (same as build-project.sh)
#   --restart  stop a running instance of the same emulator first
#   --wait     stay in the foreground until the emulator exits (default: detach)
#   --dry-run  print the command as IMPRESSION_CMD=... instead of launching
# Exit codes: 0 ok, 1 build/launch failed, 2 usage, 3 environment (e.g. no PCSX2_PATH).
# Detached launches print IMPRESSION_PID=<pid>. See docs/tooling-contract.md.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

project="" build=0 restart=0 wait_exit=0 dry_run=0
for arg in "$@"; do
    case "$arg" in
        -h | --help)
            sed -n '5,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
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

load_config
[ -n "${PCSX2_PATH:-}" ] || die "$EXIT_ENV" "PCSX2_PATH is not set. Copy impression.local.conf.example to impression.local.conf and set it."

resolve_project "$project"

if [ "$build" -eq 1 ]; then
    "$IMPRESSION_ROOT/scripts/build-project.sh" "$PROJECT_REL" || exit $?
fi
find_elf

# Locate the emulator: PCSX2_PATH is either the executable or its directory.
emu=""
if [ -f "$PCSX2_PATH" ]; then
    emu="$PCSX2_PATH"
elif [ -d "$PCSX2_PATH" ]; then
    for name in pcsx2-qt pcsx2 PCSX2; do
        if [ -f "$PCSX2_PATH/$name" ] && [ -x "$PCSX2_PATH/$name" ]; then
            emu="$PCSX2_PATH/$name"
            break
        fi
    done
fi
[ -n "$emu" ] || die "$EXIT_ENV" "PCSX2 executable not found at PCSX2_PATH=$PCSX2_PATH"

# Old wx-based builds take --elf=<file>; the Qt builds take -elf <file>.
emu_name="$(basename "$emu" | tr '[:upper:]' '[:lower:]')"
if { [ "$emu_name" = "pcsx2" ] || [ "$emu_name" = "pcsx2x64" ]; } && [ ! -f "$(dirname "$emu")/qt.conf" ]; then
    elf_args=("--elf=$ELF")
else
    elf_args=(-elf "$ELF")
fi

# Extra flags from PCSX2_ARGS are split on whitespace (no quoting support).
extra_args=()
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
    exit 0
fi

if [ "$restart" -eq 1 ]; then
    pkill -f -- "$emu" || true
    sleep 1
fi

if [ "$wait_exit" -eq 1 ]; then
    "${cmd[@]}" || true
    exit 0
fi

nohup "${cmd[@]}" >/dev/null 2>&1 &
pid=$!
disown "$pid" 2>/dev/null || true
echo "IMPRESSION_PID=$pid"
