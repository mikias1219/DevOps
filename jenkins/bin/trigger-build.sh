#!/usr/bin/env bash
# Trigger a Jenkins job: ./jenkins/trigger-build.sh <job-name> [ACTION]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JOB_NAME="${1:-collaboration-stack}"
ACTION="${ACTION:-${2:-start}}"
SKIP_TESTS="${SKIP_TESTS:-true}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-DevOps@2026}"

AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}"

COOKIE_JAR="$(mktemp)"
CRUMB_JSON="$(curl -sf -u "$AUTH" -c "$COOKIE_JAR" "$JENKINS_URL/crumbIssuer/api/json" || echo '{}')"
CRUMB_FIELD="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("crumbRequestField",""))' <<<"$CRUMB_JSON")"
CRUMB_VALUE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("crumb",""))' <<<"$CRUMB_JSON")"

curl_args=()
if [[ -n "$CRUMB_FIELD" && -n "$CRUMB_VALUE" ]]; then
  curl_args+=(-H "${CRUMB_FIELD}: ${CRUMB_VALUE}")
fi

echo "==> Triggering ${JOB_NAME} (ACTION=${ACTION})"
LOCATION="$(
  curl -sS -D - -o /dev/null -u "$AUTH" -b "$COOKIE_JAR" \
    "${curl_args[@]}" \
    -X POST \
    --data-urlencode "ACTION=${ACTION}" \
    --data-urlencode "SKIP_TESTS=${SKIP_TESTS}" \
    "$JENKINS_URL/job/${JOB_NAME}/buildWithParameters" \
    | awk 'BEGIN{IGNORECASE=1} /^Location:/ {print $2}' | tr -d '\r'
)"

rm -f "$COOKIE_JAR"

if [[ -z "$LOCATION" ]]; then
  echo "Build queued. Open ${JENKINS_URL}/job/${JOB_NAME}/"
  exit 0
fi

echo "Queue: ${LOCATION}"
for _ in $(seq 1 60); do
  BODY="$(curl -sf -u "$AUTH" "${LOCATION}api/json" || true)"
  NUM="$(python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); print((d.get("executable") or {}).get("number") or "")
except Exception:
 print("")' <<<"$BODY")"
  if [[ -n "$NUM" ]]; then
    echo "Build #${NUM}: ${JENKINS_URL}/job/${JOB_NAME}/${NUM}/"
    echo "Console: ${JENKINS_URL}/job/${JOB_NAME}/${NUM}/console"
    exit 0
  fi
  sleep 1
done

echo "Still queued — open ${JENKINS_URL}/job/${JOB_NAME}/"
