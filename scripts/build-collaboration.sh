#!/usr/bin/env bash
# Build Collaboration Docker images (no local node_modules needed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/collaboration/.env.docker"
SOURCE="$(grep '^COLLABORATION_SOURCE=' "$ENV_FILE" | cut -d= -f2-)"

"$ROOT/scripts/sync-env-from-projects.sh"

docker build -f "$ROOT/collaboration/docker/backend.Dockerfile" \
  -t collaboration-backend:local "$SOURCE/backend"

docker build -f "$ROOT/collaboration/docker/frontend.Dockerfile" \
  --build-arg NEXT_PUBLIC_COLLABORATION_URL=http://localhost:5000/api/v1 \
  --build-arg NEXT_PUBLIC_WS_URL=http://localhost:5000 \
  --build-arg NEXT_PUBLIC_API_URL=http://localhost:5000/api/v1 \
  -t collaboration-frontend:local "$SOURCE/frontend"

echo "Images built: collaboration-backend:local, collaboration-frontend:local"
