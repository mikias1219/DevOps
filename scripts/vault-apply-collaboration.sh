#!/usr/bin/env bash
# Export from Vault and recreate Collaboration containers.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TARGET="${TARGET:-both}"
"$ROOT/scripts/vault-export-collaboration-env.sh"
COMPOSE="$ROOT/collaboration/docker-compose.yml"
ENV_FILE="$ROOT/collaboration/.env.docker"
case "$TARGET" in
  backend)  docker compose -f "$COMPOSE" --env-file "$ENV_FILE" up -d --force-recreate backend ;;
  frontend) docker compose -f "$COMPOSE" --env-file "$ENV_FILE" up -d --force-recreate frontend ;;
  both)     docker compose -f "$COMPOSE" --env-file "$ENV_FILE" up -d --force-recreate backend frontend ;;
esac
docker compose -f "$COMPOSE" --env-file "$ENV_FILE" ps
