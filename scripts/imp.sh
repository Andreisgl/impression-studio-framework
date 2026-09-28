#!/usr/bin/env bash
# Copyright 2026 Andrei Segal
# SPDX-License-Identifier: Apache-2.0

# Host launcher for the toolchain container. Usage: scripts/imp.sh [-p <project>] <command> [args...]
#   start | stop | restart | status | shell      manage the long-lived container
#   rebuild-image                                rebuild the toolchain image
#   build | clean | make [args]                  act on the project
#   build-engine | clean-engine                  Tyra's engine library
#   build-framework | clean-framework            the framework library
#   sync-ide                                     (re)generate the project's
#                                                 IntelliSense config
# The container is started automatically when a command needs it. The project is
# -p <folder>, else the PROJECT_DIR environment variable, else project/.
# Exit codes: 0 ok, 1 build failed, 2 usage, 3 environment. docs/tooling-contract.md
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

project_arg=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p | --project)
            [ "$#" -ge 2 ] || die "$EXIT_USAGE" "$1 needs a folder"
            project_arg="$2"
            shift 2
            ;;
        -h | --help)
            sed -n '5,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) break ;;
    esac
done
[ "$#" -ge 1 ] || die "$EXIT_USAGE" "missing command (try: imp.sh --help)"
command=$1
shift

case "$command" in
    status)
        need_docker
        state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not created")"
        echo "$CONTAINER: $state"
        ;;
    stop)
        need_docker
        docker stop "$CONTAINER" >/dev/null 2>&1 || true
        echo "$CONTAINER stopped"
        ;;
    rebuild-image)
        need_docker
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        docker rmi "$IMAGE" >/dev/null 2>&1 || true
        ensure_images
        ;;
    start | restart | shell | build | clean | make | build-engine | clean-engine | build-framework | clean-framework | sync-ide)
        resolve_project "$project_arg"
        load_project_config
        need_docker
        if [ "$command" = "restart" ]; then docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; fi
        ensure_container
        case "$command" in
            start | restart) echo "$CONTAINER running (project: $PROJECT_ABS)" ;;
            shell) docker exec -it -w /project "$CONTAINER" bash ;;
            *) container_imp "$command" "$@" ;;
        esac
        ;;
    *)
        die "$EXIT_USAGE" "unknown command: $command"
        ;;
esac
