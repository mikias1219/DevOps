#!/usr/bin/env bash
# Copy project .env files into docker-devops (Docker-only runtime config).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HK_ENV="$ROOT/housekeeper/.env.docker"
COL_ENV="$ROOT/collaboration/.env.docker"

HOUSEKEEPER_SOURCE="$(grep '^HOUSEKEEPER_SOURCE=' "$HK_ENV" | cut -d= -f2-)"
COLLABORATION_SOURCE="$(grep '^COLLABORATION_SOURCE=' "$COL_ENV" | cut -d= -f2-)"

mkdir -p "$ROOT/collaboration/env"

if [[ -f "$COLLABORATION_SOURCE/backend/.env" ]]; then
  cp "$COLLABORATION_SOURCE/backend/.env" "$ROOT/collaboration/env/backend.env"
  # Docker network overrides
  sed -i \
    -e 's/^DB_HOST=.*/DB_HOST=db/' \
    -e 's/^DB_PORT=.*/DB_PORT=5432/' \
    -e 's/^DB_NAME=.*/DB_NAME=selamnew-collab/' \
    -e 's/^DB_PASSWORD=.*/DB_PASSWORD=collab_secret/' \
    -e 's/^REDIS_HOST=.*/REDIS_HOST=redis/' \
    -e 's/^REDIS_PORT=.*/REDIS_PORT=6379/' \
    -e 's|^ELASTICSEARCH_NODE=.*|ELASTICSEARCH_NODE=http://elasticsearch:9200|' \
    -e 's/^APP_PORT=.*/APP_PORT=5000/' \
    -e 's|^APP_PUBLIC_BASE_URL=.*|APP_PUBLIC_BASE_URL=http://localhost:5000|' \
    -e 's|^COLLABORATION_FRONT_URL=.*|COLLABORATION_FRONT_URL=http://localhost:3000|' \
    "$ROOT/collaboration/env/backend.env"
  echo "Synced collaboration/env/backend.env"
else
  echo "Missing $COLLABORATION_SOURCE/backend/.env" >&2
  exit 1
fi

if [[ -f "$COLLABORATION_SOURCE/frontend/.env" ]]; then
  cp "$COLLABORATION_SOURCE/frontend/.env" "$ROOT/collaboration/env/frontend.env"
  sed -i \
    -e 's|^NEXT_PUBLIC_COLLABORATION_URL=.*|NEXT_PUBLIC_COLLABORATION_URL=http://localhost:5000/api/v1|' \
    -e 's|^NEXT_PUBLIC_WS_URL=.*|NEXT_PUBLIC_WS_URL=http://localhost:5000|' \
    -e 's|^NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=http://localhost:5000/api/v1|' \
    -e 's/^PORT=.*/PORT=3001/' \
    "$ROOT/collaboration/env/frontend.env"
  echo "Synced collaboration/env/frontend.env"
fi

echo "Done. Env files live under docker-devops only — use Docker/Jenkins to run apps."
