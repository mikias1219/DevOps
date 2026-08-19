#!/usr/bin/env bash
# Remove unused Docker images, containers, networks, and build cache.
set -euo pipefail

echo "==> Docker disk usage BEFORE cleanup"
docker system df

echo
echo "==> Removing stopped containers"
docker container prune -f

echo
echo "==> Removing dangling images"
docker image prune -f

echo
echo "==> Removing unused networks"
docker network prune -f

echo
echo "==> Removing build cache (reclaimable space)"
docker builder prune -af

echo
echo "==> Docker disk usage AFTER cleanup"
docker system df

echo
echo "Done. Named volumes (database data) were NOT removed."
echo "To also remove unused volumes: docker volume prune -f"
