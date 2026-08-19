#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/build-collaboration.sh"
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" up -d "$@"
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" ps
