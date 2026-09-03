#!/usr/bin/env bash
# Build + push all app images on the HOST (no Jenkins timeout).
# Then Jenkins ACTION=recreate finishes in ~30 seconds.
#
# Usage:
#   ./scripts/build-images-on-host.sh           # all three
#   ./scripts/build-images-on-host.sh backend
#   ./scripts/build-images-on-host.sh frontend notification
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${COLLABORATION_SOURCE:-/home/ienetworks/workspace/company/SelamnewCollaboration}"
REG="${REGISTRY:-127.0.0.1:5001}"
LAB_NODE="${REG}/lab-node:20"

log() { echo "==> $*"; }

. "${ROOT}/jenkins/lib/docker-lib.sh"
DEVOPS_ROOT="$ROOT"
ENV_FILE="${ROOT}/collaboration/.env.docker"
NOTIFICATION_ENV_FILE="${ROOT}/notification/.env.docker"
COMPOSE_FILE="${ROOT}/collaboration/docker-compose.yml"
REGISTRY_COMPOSE="${ROOT}/registry/docker-compose.yml"

ensure_local_registry
bash "${ROOT}/scripts/warm-lab-base.sh"

TARGETS=("$@")
if [ "${#TARGETS[@]}" -eq 0 ]; then
  TARGETS=(backend frontend notification)
fi

for t in "${TARGETS[@]}"; do
  case "$t" in
    backend)
      log "HOST build backend"
      build_and_push_collaboration_backend
      ;;
    frontend)
      log "HOST build frontend"
      build_and_push_collaboration_frontend
      ;;
    notification)
      log "HOST build notification"
      build_and_push_collaboration_notification
      ;;
    *)
      echo "Unknown target: $t (backend|frontend|notification)" >&2
      exit 1
      ;;
  esac
done

log "Registry: $(curl -sf "http://${REG}/v2/_catalog")"
log "Next: Jenkins → collaboration-* ACTION=recreate (fast deploy only)"
