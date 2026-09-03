#!/usr/bin/env bash
# Pre-build the slow apt+npm deps layer once on the host (outside Jenkins timeout).
# Safe to re-run — uses Docker layer cache.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${COLLABORATION_SOURCE:-/home/ienetworks/workspace/company/SelamnewCollaboration}"
DEVOPS="${DEVOPS_ROOT:-$ROOT}"

log() { echo "==> $*"; }

warm() {
  _name="$1"
  _dockerfile="$2"
  _context="$3"
  log "Warm deps: ${_name}"
  DOCKER_BUILDKIT=0 docker build \
    -f "$_dockerfile" \
    --target deps \
    -t "lab-warm-${_name}:deps" \
    "$_context"
}

warm backend "${DEVOPS}/collaboration/docker/backend.Dockerfile" "${SRC}/backend"
warm notification "${DEVOPS}/notification/docker/notification.Dockerfile" "${SRC}/Notification-and-email-service"
warm frontend "${DEVOPS}/collaboration/docker/frontend.Dockerfile" "${SRC}/frontend"

log "Deps layers cached — Jenkins build-and-start should skip apt/npm on cache hit"
