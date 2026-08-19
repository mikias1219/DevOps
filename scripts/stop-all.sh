#!/usr/bin/env bash
# Stop all DevOps project stacks (keeps volumes/data).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Stopping Collaboration"
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" down 2>/dev/null || true

echo "==> Stopping Housekeeper"
docker compose -f "$ROOT/housekeeper/docker-compose.yml" --env-file "$ROOT/housekeeper/.env.docker" down 2>/dev/null || true

echo "==> Stopping Jenkins"
docker compose -f "$ROOT/jenkins/docker-compose.yml" down 2>/dev/null || true

echo "==> Stopping Portainer"
docker compose -f "$ROOT/portainer/docker-compose.yml" down 2>/dev/null || true

echo "Done. Data volumes preserved."
