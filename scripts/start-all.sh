#!/usr/bin/env bash
# Start all DevOps services: Portainer, Jenkins, Housekeeper, Collaboration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DOCKER_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 124)"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable. Start Docker and retry." >&2
  exit 1
fi

for project in housekeeper collaboration; do
  if [[ ! -f "$ROOT/$project/.env.docker" ]]; then
    cp "$ROOT/$project/.env.docker.example" "$ROOT/$project/.env.docker"
    echo "Created $project/.env.docker from example"
  fi
done

echo "==> Starting Portainer"
if docker ps --format '{{.Names}}' | grep -qx portainer; then
  echo "    Portainer already running — skipped"
else
  docker compose -f "$ROOT/portainer/docker-compose.yml" up -d
fi

echo "==> Starting Jenkins"
docker compose -f "$ROOT/jenkins/docker-compose.yml" up -d --build

echo "==> Starting Housekeeper stack"
docker compose -f "$ROOT/housekeeper/docker-compose.yml" --env-file "$ROOT/housekeeper/.env.docker" up -d --build

echo "==> Starting Collaboration stack"
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" up -d --build

echo
echo "==> Running containers"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
echo "URLs:"
echo "  Portainer:              https://localhost:9443"
echo "  Jenkins:                http://localhost:8080"
echo "  Housekeeper Web:        http://localhost:3001"
echo "  Housekeeper API:        http://localhost:4000/api/v1/health"
echo "  Collaboration Frontend: http://localhost:3000"
echo "  Collaboration Backend:  http://localhost:5000/api/v1"
