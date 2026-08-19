#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker compose -f "$ROOT/housekeeper/docker-compose.yml" --env-file "$ROOT/housekeeper/.env.docker" stop "$@"
