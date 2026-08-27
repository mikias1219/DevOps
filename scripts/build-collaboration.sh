#!/usr/bin/env bash
# Build and push Collaboration images to the local registry (no Jenkins).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/jenkins/lib/docker-lib.sh"
export DEVOPS_ROOT="$ROOT"
export COMPOSE_FILE="$ROOT/collaboration/docker-compose.yml"
export ENV_FILE="$ROOT/collaboration/.env.docker"
ensure_local_registry
build_and_push_collaboration_backend
build_and_push_collaboration_frontend
