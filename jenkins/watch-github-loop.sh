#!/bin/sh
# Quiet GitHub checker. Does NOT create a Jenkins build unless a remote SHA changed.
set -eu

JENKINS_URL="${JENKINS_URL:-http://jenkins:8080}"
WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-30}"
export JENKINS_URL

# shellcheck source=/dev/null
. /var/devops/jenkins/docker-lib.sh

echo "github-watch: waiting for Jenkins at ${JENKINS_URL}"
i=0
while [ "$i" -lt 60 ]; do
  if curl -sf "${JENKINS_URL}/login" >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 5
done

COL_ENV=/var/devops/collaboration/.env.docker
HK_ENV=/var/devops/housekeeper/.env.docker

echo "github-watch: checking GitHub every ${WATCH_INTERVAL_SECONDS}s; Jenkins builds only on SHA change"

while true; do
  COL_SRC="$(grep '^COLLABORATION_SOURCE=' "$COL_ENV" | cut -d= -f2-)"
  COL_BACK_BR="$(grep '^COLLABORATION_BACKEND_BRANCH=' "$COL_ENV" | cut -d= -f2- || echo develop)"
  COL_FE_BR="$(grep '^COLLABORATION_FRONTEND_BRANCH=' "$COL_ENV" | cut -d= -f2- || echo develop)"

  HK_SRC="$(grep '^HOUSEKEEPER_SOURCE=' "$HK_ENV" | cut -d= -f2-)"
  HK_BACK_BR="$(grep '^HOUSEKEEPER_BACKEND_BRANCH=' "$HK_ENV" | cut -d= -f2- || echo main)"
  HK_FE_BR="$(grep '^HOUSEKEEPER_FRONTEND_BRANCH=' "$HK_ENV" | cut -d= -f2- || echo main)"

  pending=0

  if github_change_pending collaboration-backend "$COL_SRC/backend" "$COL_BACK_BR"; then
    pending=1
  fi
  if github_change_pending collaboration-frontend "$COL_SRC/frontend" "$COL_FE_BR"; then
    pending=1
  fi
  if github_change_pending housekeeper-backend "$HK_SRC/backend" "$HK_BACK_BR"; then
    pending=1
  fi
  if github_change_pending housekeeper-frontend "$HK_SRC/frontend" "$HK_FE_BR"; then
    pending=1
  fi

  if [ "$pending" -eq 1 ]; then
    trigger_watch_github_job watch-github
    # Give Jenkins time to record the new SHAs so this loop does not fire twice.
    sleep 90
  fi

  sleep "$WATCH_INTERVAL_SECONDS"
done
