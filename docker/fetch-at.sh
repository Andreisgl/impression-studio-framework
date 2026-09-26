#!/bin/sh
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Fetches one exact commit of a git repository into a directory.
# Usage: fetch-at <repo-url> <commit-sha> <directory>
# GitHub allows fetching a commit by SHA, so no history is downloaded.
set -eu

[ "$#" -eq 3 ] || { echo "usage: fetch-at <repo-url> <commit-sha> <directory>" >&2; exit 2; }

git init -q "$3"
cd "$3"
git remote add origin "$1"
git fetch -q --depth 1 origin "$2"
git checkout -q FETCH_HEAD
