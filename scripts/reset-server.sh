#!/usr/bin/env bash
# Stop every DevOps lab stack and reclaim Docker disk space.
# Does NOT delete application source repos under COLLABORATION_SOURCE.
#
# Usage:
#   ./scripts/reset-server.sh              # stop stacks, prune dangling images
#   ./scripts/reset-server.sh --wipe-volumes   # also remove named volumes (DB data, Jenkins home)
#   ./scripts/reset-server.sh --wipe-all       # volumes + local registry images + build cache
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIPE_VOLUMES=false
WIPE_ALL=false

for arg in "$@"; do
  case "$arg" in
    --wipe-volumes) WIPE_VOLUMES=true ;;
    --wipe-all) WIPE_VOLUMES=true; WIPE_ALL=true ;;
    -h | --help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

log() { echo "==> $*"; }

compose_down() {
  local file="$1"
  local env_file="${2:-}"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  log "Stopping $(basename "$(dirname "$file")")"
  if [[ -n "$env_file" && -f "$env_file" ]]; then
    docker compose -f "$file" --env-file "$env_file" down --remove-orphans 2>/dev/null || true
  else
    docker compose -f "$file" down --remove-orphans 2>/dev/null || true
  fi
}

log "Stopping DevOps stacks"
compose_down "$ROOT/collaboration/docker-compose.yml" "$ROOT/collaboration/.env.docker"
compose_down "$ROOT/notification/docker-compose.yml" "$ROOT/notification/.env.docker"
compose_down "$ROOT/jenkins/docker-compose.yml"
compose_down "$ROOT/vault/docker-compose.yml"
compose_down "$ROOT/secrets-room/docker-compose.yml"
compose_down "$ROOT/registry/docker-compose.yml"
compose_down "$ROOT/portainer/docker-compose.yml"

log "Removing stopped containers"
docker container prune -f

if [[ "$WIPE_VOLUMES" == true ]]; then
  log "Removing DevOps named volumes"
  for vol in \
    collaboration_pgdata collaboration_redis collaboration_esdata \
    notification_pgdata \
    jenkins_jenkins_home jenkins_home \
    devops-registry_registry_data \
    portainer_portainer_data \
    vault_vault_data vault_vault_logs; do
    docker volume rm "$vol" 2>/dev/null || true
  done
  # Compose project-prefixed names (collaboration_*, jenkins_*, etc.)
  docker volume ls -q | grep -E '^(collaboration_|jenkins_|notification_|devops-registry_|portainer_|vault_|selamnew-)' \
    | xargs -r docker volume rm 2>/dev/null || true
fi

log "Removing dangling images and build cache"
docker image prune -f
docker builder prune -f 2>/dev/null || true

if [[ "$WIPE_ALL" == true ]]; then
  log "Removing unused images (not running)"
  docker image prune -af
  docker builder prune -af 2>/dev/null || true
fi

log "Docker disk usage"
docker system df

echo
echo "Reset complete."
echo "  App source repos were NOT deleted."
echo "  Server secrets (collaboration/env, jenkins/secrets, vault/secrets) were kept."
echo "Next: bash scripts/bootstrap-learning-server.sh"
