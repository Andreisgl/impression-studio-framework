#!/bin/sh
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Pins the compiler sources a ps2toolchain-* script set downloads.
#
# Those scripts clone binutils, GCC and newlib from ps2dev's forks by branch name,
# so they take whatever the branch head is today; newlib's head has changed since
# 2022 and no longer builds with GCC 11.3. This rewrites each script to fetch one
# exact commit instead (the newest on that branch at or before 2022-07-05 20:30 UTC,
# the snapshot this image reproduces) and to never move off it on later passes.
#
# Usage: pin-sources <scripts-dir>     (uses fetch-at, docker/fetch-at.sh)
# Fails if a script names a repository/branch that has no pin below, so a changed
# script set cannot silently fall back to an unpinned branch head.
set -eu

[ "$#" -eq 1 ] || { echo "usage: pin-sources <scripts-dir>" >&2; exit 2; }

# folder|branch -> commit
lookup() {
    case "$1|$2" in
        'binutils-gdb|ee-v2.38.0') echo ef67f1355b6440e79bf578e8204fda1403f31985 ;;
        'gcc|ee-v11.3.0') echo b24ab55b52dd201bb83769ed2a5857b645207568 ;;
        'newlib|ee-v4.1.0') echo 6b90d31371ff4e0f41d64d7539038864899a6b40 ;;
        # This branch was rewritten in 2024 (the July 2022 head with the IOP/IRX patches
        # no longer exists; the old release commit lacks IRX support), so this is the
        # head at the time of pinning: the same IOP patch set, re-applied.
        'binutils-gdb|iop-v2.35.2') echo 11665c617a6175742473fe141fe0d67dad58a4ad ;;
        'gcc|iop-v11.3.0') echo 331453616ac96717cfef82d21c03573c8984f17d ;;
        'binutils-gdb|dvp-v2.14') echo 9cca5c1781d1a03b9b3b61a3e5270cdb9c69295e ;;
        *) return 1 ;;
    esac
}

for file in "$1"/*.sh; do
    branch="$(sed -n 's/^BRANCH_NAME="\(.*\)"$/\1/p' "$file")"
    [ -n "$branch" ] || continue
    folder="$(sed -n 's/^REPO_FOLDER="\(.*\)"$/\1/p' "$file")"
    sha="$(lookup "$folder" "$branch")" || { echo "pin-sources: no pin for $folder@$branch ($file)" >&2; exit 1; }

    sed -i \
        -e "s|^BRANCH_NAME=.*|&\nPINNED_SHA=\"$sha\"|" \
        -e 's|git clone --depth 1 -b "\$BRANCH_NAME" "\$REPO_URL"|fetch-at "$REPO_URL" "$PINNED_SHA" "$REPO_FOLDER"|' \
        -e 's|git -C "\$REPO_FOLDER" fetch origin|true|' \
        -e 's|git -C "\$REPO_FOLDER" reset --hard "origin/\${BRANCH_NAME}"|git -C "$REPO_FOLDER" reset --hard "$PINNED_SHA"|' \
        -e 's|git -C "\$REPO_FOLDER" checkout "\$BRANCH_NAME"|true|' \
        "$file"

    if grep -q -E 'git clone|origin/|checkout "\$BRANCH_NAME"' "$file"; then
        echo "pin-sources: $file still fetches an unpinned branch head" >&2
        exit 1
    fi
    echo "pinned $file: $folder@$branch -> $sha"
done
