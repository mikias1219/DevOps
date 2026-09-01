#!/usr/bin/env bash
# Stop stuck Jenkins builds, prune Docker cache, keep running app containers.
set -euo pipefail

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-DevOps@2026}"
AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}"

log() { echo "==> $*"; }

log "Stopping stuck Jenkins builds (if any)"
for job in collaboration-backend collaboration-frontend collaboration-notification; do
  num="$(curl -sf -u "$AUTH" "${JENKINS_URL}/job/${job}/lastBuild/api/json" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("number","")) if d.get("building") else print("")' 2>/dev/null || true)"
  if [[ -n "$num" ]]; then
    started="$(curl -sf -u "$AUTH" "${JENKINS_URL}/job/${job}/${num}/api/json" \
      | python3 -c 'import sys,json,time; d=json.load(sys.stdin); print(int((time.time()*1000-d.get("timestamp",0))/60000))' 2>/dev/null || echo 999)"
    if [[ "$started" -gt 25 ]]; then
      log "Abort ${job} #${num} (running ${started}m — likely stuck on slow npm/chown)"
      curl -sf -u "$AUTH" -X POST "${JENKINS_URL}/job/${job}/${num}/stop" >/dev/null || true
    fi
  fi
done

log "Prune Docker build cache and stopped containers (running apps untouched)"
docker builder prune -af >/dev/null 2>&1 || docker builder prune -f >/dev/null 2>&1 || true
docker container prune -f >/dev/null
docker image prune -f >/dev/null

log "Disk after cleanup"
docker system df 2>/dev/null || true

log "Done — re-run app jobs with ACTION=recreate (fast) or build-and-start (first image only)"
