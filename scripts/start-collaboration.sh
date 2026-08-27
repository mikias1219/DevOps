#!/usr/bin/env bash
# Bootstrap helper. Prefer Jenkins ACTION=build-and-start for images.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/jenkins/lib/docker-lib.sh"
export DEVOPS_ROOT="$ROOT"
export COMPOSE_FILE="$ROOT/collaboration/docker-compose.yml"
export ENV_FILE="$ROOT/collaboration/.env.docker"

ensure_local_registry
ensure_collaboration_infra
if [[ "${1:-}" == "--build" ]]; then
  build_and_push_collaboration_backend
  build_and_push_collaboration_frontend
  deploy_collaboration_service backend
  deploy_collaboration_service frontend
else
  echo "Infra is up. Build app images with:"
  echo "  $0 --build"
  echo "  or Jenkins → collaboration-stack ACTION=build-and-start"
fi
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
