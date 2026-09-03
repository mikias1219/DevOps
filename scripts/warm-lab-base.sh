#!/usr/bin/env bash
# Build lab-node:20 once (apt tools). App Jenkins builds then skip apt entirely.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="${REGISTRY:-127.0.0.1:5001}"
IMAGE="${REG}/lab-node:20"

log() { echo "==> $*"; }

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  log "Already have ${IMAGE}"
  exit 0
fi

log "Building ${IMAGE} (one-time apt — may take 20–40m on slow lab network)"
DOCKER_BUILDKIT=1 docker build \
  -f "${ROOT}/collaboration/docker/lab-node.Dockerfile" \
  -t "$IMAGE" \
  "${ROOT}/collaboration/docker"

if curl -sf "http://${REG}/v2/" >/dev/null 2>&1; then
  log "Pushing ${IMAGE}"
  docker push "$IMAGE" || true
fi

log "Done — app Dockerfiles use this base (no more apt-get)"
