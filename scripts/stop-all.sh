#!/usr/bin/env bash
# Stop stacks. Volumes and the local registry stay unless you pass --with-registry.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Stopping Collaboration"
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" down 2>/dev/null || true

echo "==> Stopping Jenkins"
docker compose -f "$ROOT/jenkins/docker-compose.yml" down 2>/dev/null || true

echo "==> Stopping Portainer"
docker compose -f "$ROOT/portainer/docker-compose.yml" down 2>/dev/null || true

if [[ "${1:-}" == "--with-registry" ]]; then
  echo "==> Stopping registry"
  docker compose -f "$ROOT/registry/docker-compose.yml" down 2>/dev/null || true
fi

echo "Done. Named volumes were not deleted."
