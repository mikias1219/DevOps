#!/usr/bin/env bash
# Copy app .env files into docker-devops (Docker-only runtime config).
# Does not modify frontend/ or backend/ repos.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COL_ENV="$ROOT/collaboration/.env.docker"
COLLABORATION_SOURCE="$(grep '^COLLABORATION_SOURCE=' "$COL_ENV" | cut -d= -f2-)"

mkdir -p "$ROOT/collaboration/env"

if [[ -f "$COLLABORATION_SOURCE/backend/.env" ]]; then
  cp "$COLLABORATION_SOURCE/backend/.env" "$ROOT/collaboration/env/backend.env"
  sed -i \
    -e 's/^DB_HOST=.*/DB_HOST=db/' \
    -e 's/^DB_PORT=.*/DB_PORT=5432/' \
    -e 's/^REDIS_HOST=.*/REDIS_HOST=redis/' \
    -e 's/^REDIS_PORT=.*/REDIS_PORT=6379/' \
    -e 's|^ELASTICSEARCH_NODE=.*|ELASTICSEARCH_NODE=http://elasticsearch:9200|' \
    -e 's/^APP_PORT=.*/APP_PORT=5000/' \
    "$ROOT/collaboration/env/backend.env"
  echo "Synced collaboration/env/backend.env"
else
  echo "Missing $COLLABORATION_SOURCE/backend/.env" >&2
  exit 1
fi

if [[ -f "$COLLABORATION_SOURCE/frontend/.env" ]]; then
  cp "$COLLABORATION_SOURCE/frontend/.env" "$ROOT/collaboration/env/frontend.env"
  echo "Synced collaboration/env/frontend.env (NEXT_PUBLIC_* are also bake-time Docker build-args)"
fi

echo "Done. Runtime env lives under docker-devops only."
