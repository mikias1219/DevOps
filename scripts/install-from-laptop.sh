#!/usr/bin/env bash
# Push docker-devops from your laptop to the learning server and bootstrap.
#
# Usage:
#   ./scripts/install-from-laptop.sh
#   ./scripts/install-from-laptop.sh --fresh     # wipe Docker volumes on server first
#   ./scripts/install-from-laptop.sh --skip-build
#
# Environment overrides:
#   SERVER=172.16.50.39  USER=ienetworks  REMOTE_DEVOPS=/home/ienetworks/workspace/tools/docker-devops
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="${SERVER:-172.16.50.39}"
SSH_USER="${SSH_USER:-ienetworks}"
REMOTE_DEVOPS="${REMOTE_DEVOPS:-/home/${SSH_USER}/workspace/tools/docker-devops}"
REMOTE="${SSH_USER}@${SERVER}"

FRESH=false
SKIP_BUILD=false
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=true; EXTRA_ARGS+=(--fresh) ;;
    --skip-build) SKIP_BUILD=true; EXTRA_ARGS+=(--skip-build) ;;
  esac
done

log() { echo "==> $*"; }

log "Syncing docker-devops → ${REMOTE}:${REMOTE_DEVOPS}"
ssh -o StrictHostKeyChecking=no "$REMOTE" "mkdir -p $(dirname "$REMOTE_DEVOPS")"

rsync -az --delete \
  --exclude '.git/' \
  --exclude '.watch-state/' \
  --exclude 'collaboration/.env.docker' \
  --exclude 'collaboration/env/*.env' \
  --exclude 'notification/.env.docker' \
  --exclude 'notification/env/*.env' \
  --exclude 'jenkins/secrets/admin.env' \
  --exclude 'jenkins/secrets/github-webhook*.txt' \
  --exclude 'vault/secrets/' \
  --exclude 'secrets-room/.env' \
  "$ROOT/" "${REMOTE}:${REMOTE_DEVOPS}/"

log "Running bootstrap on server"
ssh -o StrictHostKeyChecking=no "$REMOTE" \
  "cd '${REMOTE_DEVOPS}' && bash scripts/bootstrap-learning-server.sh ${EXTRA_ARGS[*]:-}"

echo
echo "Done. Open http://${SERVER}:8080 (Jenkins)"
