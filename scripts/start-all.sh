#!/usr/bin/env bash
# First-time / laptop bootstrap. Daily deploys go through Jenkins.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DOCKER_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 124)"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable. Start Docker and retry." >&2
  exit 1
fi

if [[ ! -f "$ROOT/collaboration/.env.docker" ]]; then
  cp "$ROOT/collaboration/.env.docker.example" "$ROOT/collaboration/.env.docker"
  echo "Created collaboration/.env.docker from example — edit COLLABORATION_SOURCE"
fi

echo "==> Local registry"
docker compose -f "$ROOT/registry/docker-compose.yml" up -d

echo "==> Portainer"
if docker ps --format '{{.Names}}' | grep -qx portainer; then
  echo "    already running"
else
  docker compose -f "$ROOT/portainer/docker-compose.yml" up -d
fi

echo "==> Jenkins"
docker compose -f "$ROOT/jenkins/docker-compose.yml" up -d --build

echo "==> Collaboration infra (db/redis/elasticsearch). Apps are image-based — run Jenkins build-and-start."
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" up -d db redis elasticsearch adminer

echo
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo
echo "Jenkins:  http://127.0.0.1:8080"
echo "Next:     Jenkins → collaboration-backend / collaboration-frontend → ACTION=build-and-start"
