#!/usr/bin/env bash
# Run on lab server: finish clones + queue Jenkins build-and-start for staging & production.
set -euo pipefail

DEVOPS="${DEVOPS:-/home/ienetworks/workspace/tools/docker-devops}"
PARENT="${PARENT:-/home/ienetworks/workspace/company/SelamnewCollaboration/environments}"

clone_if_missing() {
  local dir="$1" url="$2" branch="$3"
  [ -d "$dir/.git" ] && return 0
  mkdir -p "$(dirname "$dir")"
  git clone "$url" -b "$branch" "$dir"
}

clone_if_missing "$PARENT/production/Notification-and-email-service" \
  git@github.com:ie-network-solutions/notification-and-email-service.git production

for f in \
  collaboration/.env.docker.staging \
  collaboration/.env.docker.production \
  notification/.env.docker.staging \
  notification/.env.docker.production; do
  ex="$DEVOPS/${f}.example"
  out="$DEVOPS/$f"
  [ -f "$out" ] || { [ -f "$ex" ] && cp "$ex" "$out"; }
done

bash "$DEVOPS/scripts/configure-lab-communication.sh"

for tier in staging production; do
  for job in collaboration-backend collaboration-frontend collaboration-notification; do
    ACTION=build-and-start LAB_TIER="$tier" GIT_BRANCH="$tier" \
      bash "$DEVOPS/jenkins/bin/trigger-build.sh" "$job" build-and-start || true
    echo "queued ${job} tier=${tier}"
  done
done

echo "lab-tier-builds-bg finished $(date -Is)"
