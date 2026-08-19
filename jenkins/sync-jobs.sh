#!/usr/bin/env bash
# Create/update all Jenkins pipeline jobs (6 jobs: stack + backend + frontend per project).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
COMPOSE_FILE="$ROOT/jenkins/docker-compose.yml"
TPL="$ROOT/jenkins/job-pipeline.xml.tpl"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-DevOps@2026}"

AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}"

for _ in $(seq 1 30); do
  if curl -sf -u "$AUTH" "$JENKINS_URL/login" >/dev/null 2>&1; then
    USE_AUTH=1
    break
  fi
  if curl -sf "$JENKINS_URL/login" >/dev/null 2>&1; then
    USE_AUTH=0
    break
  fi
  sleep 2
done

if [[ "${USE_AUTH:-1}" -eq 1 ]]; then
  CURL_AUTH=(-u "$AUTH")
else
  CURL_AUTH=()
fi

COOKIE_JAR="$(mktemp)"
CRUMB_JSON="$(curl -sf "${CURL_AUTH[@]}" -c "$COOKIE_JAR" "$JENKINS_URL/crumbIssuer/api/json" || echo '{}')"
CRUMB_FIELD="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("crumbRequestField",""))' <<<"$CRUMB_JSON")"
CRUMB_VALUE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("crumb",""))' <<<"$CRUMB_JSON")"

sync_job() {
  local job_name="$1"
  local jenkinsfile="$2"
  local description="$3"
  local extra_params="${4:-}"
  local out_xml="$ROOT/jenkins/job-${job_name}.xml"

  if [[ ! -f "$jenkinsfile" ]]; then
    echo "Missing Jenkinsfile: $jenkinsfile" >&2
    return 1
  fi

  local script_b64
  script_b64="$(base64 -w0 "$jenkinsfile")"

  python3 - "$TPL" "$script_b64" "$description" "$extra_params" >"$out_xml" <<'PY'
import base64, pathlib, sys
tpl = pathlib.Path(sys.argv[1]).read_text()
script = base64.b64decode(sys.argv[2]).decode()
desc = sys.argv[3]
extra = sys.argv[4] if len(sys.argv) > 4 else ""
esc = (
    script.replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
)
desc_esc = (
    desc.encode("ascii", "replace").decode("ascii")
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
)
print(
    tpl.replace("__PIPELINE_SCRIPT__", esc)
    .replace("__JOB_DESCRIPTION__", desc_esc)
    .replace("__EXTRA_PARAMS__", extra),
    end="",
)
PY

  local exists
  exists="$(
    curl -s -o /dev/null -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
      "$JENKINS_URL/job/${job_name}/api/json"
  )"

  local http_code curl_args=()
  if [[ -n "$CRUMB_FIELD" && -n "$CRUMB_VALUE" ]]; then
    curl_args+=(-H "${CRUMB_FIELD}: ${CRUMB_VALUE}")
  fi

  if [[ "$exists" == "200" ]]; then
    echo "==> Updating job ${job_name}"
    http_code="$(
      curl -sS -o /tmp/jenkins-sync-${job_name}.out -w '%{http_code}' \
        "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
        "${curl_args[@]}" \
        -H "Content-Type: application/xml; charset=UTF-8" \
        -X POST \
        --data-binary @"$out_xml" \
        "$JENKINS_URL/job/${job_name}/config.xml"
    )"
  else
    echo "==> Creating job ${job_name}"
    http_code="$(
      curl -sS -o /tmp/jenkins-sync-${job_name}.out -w '%{http_code}' \
        "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
        "${curl_args[@]}" \
        -H "Content-Type: application/xml; charset=UTF-8" \
        -X POST \
        --data-binary @"$out_xml" \
        "$JENKINS_URL/createItem?name=${job_name}"
    )"
  fi
  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    echo "Jenkins job sync failed for ${job_name} (HTTP ${http_code})" >&2
    head -c 800 "/tmp/jenkins-sync-${job_name}.out" >&2 || true
    echo >&2
    return 1
  fi

  echo "    ${JENKINS_URL}/job/${job_name}/"
}

SKIP_TESTS_PARAM='<hudson.model.BooleanParameterDefinition>
          <name>SKIP_TESTS</name>
          <description>Skip unit tests (build-and-start only)</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>'

sync_job "housekeeper-stack" \
  "$ROOT/jenkins/Jenkinsfile.housekeeper-stack" \
  "Housekeeper — start/stop/restart the full stack (postgres + redis + api + web)"

sync_job "housekeeper-backend" \
  "$ROOT/jenkins/Jenkinsfile.housekeeper-backend" \
  "Housekeeper backend — control api container (+ postgres/redis when starting)" \
  "$SKIP_TESTS_PARAM"

sync_job "housekeeper-frontend" \
  "$ROOT/jenkins/Jenkinsfile.housekeeper-frontend" \
  "Housekeeper frontend — control web container" \
  "$SKIP_TESTS_PARAM"

sync_job "collaboration-stack" \
  "$ROOT/jenkins/Jenkinsfile.collaboration-stack" \
  "Collaboration — start/stop/restart the full stack (db + redis + elasticsearch + backend + frontend)"

sync_job "collaboration-backend" \
  "$ROOT/jenkins/Jenkinsfile.collaboration-backend" \
  "Collaboration backend — control backend container (+ infra when starting)"

sync_job "collaboration-frontend" \
  "$ROOT/jenkins/Jenkinsfile.collaboration-frontend" \
  "Collaboration frontend — control frontend container"

WATCH_TPL="$ROOT/jenkins/job-watch.xml.tpl"
sync_watch_job() {
  local job_name="$1"
  local jenkinsfile="$2"
  local description="$3"
  local out_xml="$ROOT/jenkins/job-${job_name}.xml"
  local script_b64
  script_b64="$(base64 -w0 "$jenkinsfile")"
  python3 - "$WATCH_TPL" "$script_b64" "$description" >"$out_xml" <<'PY'
import base64, pathlib, sys
tpl = pathlib.Path(sys.argv[1]).read_text()
script = base64.b64decode(sys.argv[2]).decode()
desc = sys.argv[3]
esc = (
    script.replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
)
desc_esc = (
    desc.encode("ascii", "replace").decode("ascii")
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
)
print(tpl.replace("__PIPELINE_SCRIPT__", esc).replace("__JOB_DESCRIPTION__", desc_esc), end="")
PY
  local exists http_code
  exists="$(curl -s -o /dev/null -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" "$JENKINS_URL/job/${job_name}/api/json")"
  local curl_args=()
  if [[ -n "$CRUMB_FIELD" && -n "$CRUMB_VALUE" ]]; then
    curl_args+=(-H "${CRUMB_FIELD}: ${CRUMB_VALUE}")
  fi
  if [[ "$exists" == "200" ]]; then
    echo "==> Updating job ${job_name}"
    http_code="$(curl -sS -o /tmp/jenkins-sync-${job_name}.out -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" "${curl_args[@]}" -H "Content-Type: application/xml; charset=UTF-8" -X POST --data-binary @"$out_xml" "$JENKINS_URL/job/${job_name}/config.xml")"
  else
    echo "==> Creating job ${job_name}"
    http_code="$(curl -sS -o /tmp/jenkins-sync-${job_name}.out -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" "${curl_args[@]}" -H "Content-Type: application/xml; charset=UTF-8" -X POST --data-binary @"$out_xml" "$JENKINS_URL/createItem?name=${job_name}")"
  fi
  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    echo "Jenkins job sync failed for ${job_name} (HTTP ${http_code})" >&2
    head -c 800 "/tmp/jenkins-sync-${job_name}.out" >&2 || true
    return 1
  fi
  echo "    ${JENKINS_URL}/job/${job_name}/"
}

sync_watch_job "watch-github" \
  "$ROOT/jenkins/Jenkinsfile.watch-github" \
  "Runs only when the watched branch SHA changes. Pick the branch with job switch-watch-branch first."

SWITCH_TPL="$ROOT/jenkins/job-switch-watch.xml.tpl"
sync_switch_job() {
  local job_name="$1"
  local jenkinsfile="$2"
  local description="$3"
  local out_xml="$ROOT/jenkins/job-${job_name}.xml"
  local script_b64
  script_b64="$(base64 -w0 "$jenkinsfile")"
  python3 - "$SWITCH_TPL" "$script_b64" "$description" >"$out_xml" <<'PY'
import base64, pathlib, sys
tpl = pathlib.Path(sys.argv[1]).read_text()
script = base64.b64decode(sys.argv[2]).decode()
desc = sys.argv[3]
esc = (
    script.replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
)
desc_esc = (
    desc.encode("ascii", "replace").decode("ascii")
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
)
print(tpl.replace("__PIPELINE_SCRIPT__", esc).replace("__JOB_DESCRIPTION__", desc_esc), end="")
PY
  local exists http_code
  exists="$(curl -s -o /dev/null -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" "$JENKINS_URL/job/${job_name}/api/json")"
  local curl_args=()
  if [[ -n "$CRUMB_FIELD" && -n "$CRUMB_VALUE" ]]; then
    curl_args+=(-H "${CRUMB_FIELD}: ${CRUMB_VALUE}")
  fi
  if [[ "$exists" == "200" ]]; then
    echo "==> Updating job ${job_name}"
    http_code="$(curl -sS -o /tmp/jenkins-sync-${job_name}.out -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" "${curl_args[@]}" -H "Content-Type: application/xml; charset=UTF-8" -X POST --data-binary @"$out_xml" "$JENKINS_URL/job/${job_name}/config.xml")"
  else
    echo "==> Creating job ${job_name}"
    http_code="$(curl -sS -o /tmp/jenkins-sync-${job_name}.out -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" "${curl_args[@]}" -H "Content-Type: application/xml; charset=UTF-8" -X POST --data-binary @"$out_xml" "$JENKINS_URL/createItem?name=${job_name}")"
  fi
  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    echo "Jenkins job sync failed for ${job_name} (HTTP ${http_code})" >&2
    head -c 800 "/tmp/jenkins-sync-${job_name}.out" >&2 || true
    return 1
  fi
  echo "    ${JENKINS_URL}/job/${job_name}/"
}

sync_switch_job "switch-watch-branch" \
  "$ROOT/jenkins/Jenkinsfile.switch-watch-branch" \
  "Before watch-github: list branches from GitHub, pick one, switch watch + rebuild. No manual .env.docker edit."

rm -f "$COOKIE_JAR"
echo
echo "Done. Example:"
echo "  ACTION=start  ./jenkins/trigger-build.sh housekeeper-stack"
echo "  ACTION=stop   ./jenkins/trigger-build.sh collaboration-backend"
