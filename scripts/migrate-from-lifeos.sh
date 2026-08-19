#!/usr/bin/env bash
# Migrate from old LifeOS setup: stop old containers, clean cache, start new stacks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Stopping old LifeOS containers"
docker compose -f "/home/mikias/workspace/personal/my personal project/lifeos/docker-compose.yml" \
  --env-file "/home/mikias/workspace/personal/my personal project/lifeos/.env.docker" \
  down --remove-orphans 2>/dev/null || true

docker compose -f "/home/mikias/workspace/personal/my personal project/lifeos/jenkins/docker-compose.yml" \
  down --remove-orphans 2>/dev/null || true

docker compose -f "/home/mikias/workspace/company/SelamnewCollaboration/backend/docker-compose.yml" \
  down --remove-orphans 2>/dev/null || true

echo "==> Removing old LifeOS-named containers"
docker ps -a --format '{{.ID}} {{.Names}}' \
  | grep -iE 'lifeos|backend-redis-1|backend-elasticsearch-1' \
  | awk '{print $1}' \
  | xargs -r docker rm -f || true

echo "==> Removing old LifeOS images"
docker images -a --format '{{.ID}} {{.Repository}}:{{.Tag}}' \
  | grep -iE 'lifeos' \
  | awk '{print $1}' \
  | xargs -r docker rmi -f || true

echo "==> Cleaning Docker cache"
"$ROOT/scripts/cleanup-docker.sh"

echo "==> Starting new DevOps stacks"
"$ROOT/scripts/start-all.sh"
