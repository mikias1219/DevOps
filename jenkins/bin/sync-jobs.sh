#!/usr/bin/env bash
# Create/update Jenkins pipeline jobs from Jenkinsfiles in this repo.
# Source of truth = GitHub DevOps. Run after git pull, or via job
# sync-devops-control-plane (GitHub webhook).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JOBS_DIR="$ROOT/jenkins/jobs"
TPL="$ROOT/jenkins/templates/job-pipeline.xml.tpl"
SECRETS_DIR="$ROOT/jenkins/secrets"
OUT_DIR="${TMPDIR:-/tmp}/jenkins-sync"
JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
mkdir -p "$OUT_DIR"

if [[ -f "$SECRETS_DIR/admin.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/admin.env"
  set +a
fi
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-}"

if [[ -z "$JENKINS_ADMIN_PASS" ]]; then
  echo "WARN: JENKINS_ADMIN_PASS unset. Copy jenkins/secrets/admin.env.example → admin.env" >&2
fi

AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}"

for _ in $(seq 1 30); do
  if [[ -n "$JENKINS_ADMIN_PASS" ]] && curl -sf -u "$AUTH" "$JENKINS_URL/login" >/dev/null 2>&1; then
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

curl_crumb=()
if [[ -n "$CRUMB_FIELD" && -n "$CRUMB_VALUE" ]]; then
  curl_crumb+=(-H "${CRUMB_FIELD}: ${CRUMB_VALUE}")
fi

post_job_xml() {
  local job_name="$1"
  local out_xml="$2"
  local exists http_code
  exists="$(
    curl -s -o /dev/null -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
      "$JENKINS_URL/job/${job_name}/api/json"
  )"
  if [[ "$exists" == "200" ]]; then
    echo "==> Updating job ${job_name}"
    http_code="$(
      curl -sS -o "${OUT_DIR}/post-${job_name}.out" -w '%{http_code}' \
        "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
        "${curl_crumb[@]}" \
        -H "Content-Type: application/xml; charset=UTF-8" \
        -X POST \
        --data-binary @"$out_xml" \
        "$JENKINS_URL/job/${job_name}/config.xml"
    )"
  else
    echo "==> Creating job ${job_name}"
    http_code="$(
      curl -sS -o "${OUT_DIR}/post-${job_name}.out" -w '%{http_code}' \
        "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
        "${curl_crumb[@]}" \
        -H "Content-Type: application/xml; charset=UTF-8" \
        -X POST \
        --data-binary @"$out_xml" \
        "$JENKINS_URL/createItem?name=${job_name}"
    )"
  fi
  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    echo "Jenkins job sync failed for ${job_name} (HTTP ${http_code})" >&2
    head -c 800 "${OUT_DIR}/post-${job_name}.out" >&2 || true
    echo >&2
    return 1
  fi
  echo "    ${JENKINS_URL}/job/${job_name}/"
}

delete_job() {
  local job_name="$1"
  local exists
  exists="$(
    curl -s -o /dev/null -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
      "$JENKINS_URL/job/${job_name}/api/json"
  )"
  if [[ "$exists" != "200" ]]; then
    echo "==> Job ${job_name} not present — skip delete"
    return 0
  fi
  echo "==> Deleting job ${job_name}"
  curl -sS -o /dev/null -w '%{http_code}' "${CURL_AUTH[@]}" -b "$COOKIE_JAR" \
    "${curl_crumb[@]}" -X POST "$JENKINS_URL/job/${job_name}/doDelete" >/dev/null || true
}

sync_job() {
  local job_name="$1"
  local jenkinsfile="$2"
  local description="$3"
  local extra_params="${4:-}"
  local out_xml="${OUT_DIR}/job-${job_name}.xml"

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

  post_job_xml "$job_name" "$out_xml"
}

sync_gwt_job() {
  local job_name="$1"
  local jenkinsfile="$2"
  local description="$3"
  local token_file="$4"
  local out_xml="${OUT_DIR}/job-${job_name}.xml"
  local token="changeme"

  if [[ -f "$token_file" ]]; then
    token="$(tr -d '[:space:]' <"$token_file")"
  else
    echo "WARN: missing ${token_file} — using placeholder token; update before GitHub webhook" >&2
  fi

  if [[ ! -f "$jenkinsfile" ]]; then
    echo "Missing Jenkinsfile: $jenkinsfile" >&2
    return 1
  fi

  local script_b64
  script_b64="$(base64 -w0 "$jenkinsfile")"

  python3 - "$script_b64" "$description" "$token" >"$out_xml" <<'PY'
import base64, html, sys
script = base64.b64decode(sys.argv[1]).decode()
desc = sys.argv[2]
token = sys.argv[3]
esc = html.escape(script)
desc_esc = html.escape(desc.encode("ascii", "replace").decode("ascii"))
token_esc = html.escape(token)
print(f"""<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>{desc_esc}</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.gwt.JobPropertyImpl plugin="generic-webhook-trigger">
      <triggers>
        <org.jenkinsci.plugins.gwt.GenericTrigger>
          <spec></spec>
          <genericVariables>
            <org.jenkinsci.plugins.gwt.GenericVariable>
              <expressionType>JSONPath</expressionType>
              <key>gh_ref</key>
              <value>$.ref</value>
              <regexpFilter></regexpFilter>
              <defaultValue></defaultValue>
            </org.jenkinsci.plugins.gwt.GenericVariable>
            <org.jenkinsci.plugins.gwt.GenericVariable>
              <expressionType>JSONPath</expressionType>
              <key>gh_after</key>
              <value>$.after</value>
              <regexpFilter></regexpFilter>
              <defaultValue></defaultValue>
            </org.jenkinsci.plugins.gwt.GenericVariable>
            <org.jenkinsci.plugins.gwt.GenericVariable>
              <expressionType>JSONPath</expressionType>
              <key>gh_repo</key>
              <value>$.repository.full_name</value>
              <regexpFilter></regexpFilter>
              <defaultValue></defaultValue>
            </org.jenkinsci.plugins.gwt.GenericVariable>
          </genericVariables>
          <regexpFilterText></regexpFilterText>
          <regexpFilterExpression></regexpFilterExpression>
          <printContributedVariables>true</printContributedVariables>
          <printPostContent>false</printPostContent>
          <causeString>GitHub push webhook ($gh_repo $gh_ref)</causeString>
          <token>{token_esc}</token>
          <tokenCredentialId></tokenCredentialId>
          <silentResponse>false</silentResponse>
          <overrideQuietPeriod>false</overrideQuietPeriod>
          <shouldNotFlatten>false</shouldNotFlatten>
        </org.jenkinsci.plugins.gwt.GenericTrigger>
      </triggers>
    </org.jenkinsci.plugins.gwt.JobPropertyImpl>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>{esc}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
""")
PY

  post_job_xml "$job_name" "$out_xml"
}

sync_choice_job() {
  local job_name="$1"
  local jenkinsfile="$2"
  local description="$3"
  local param_name="$4"
  local choices_csv="$5"
  local out_xml="${OUT_DIR}/job-${job_name}.xml"
  local script_b64
  script_b64="$(base64 -w0 "$jenkinsfile")"

  python3 - "$script_b64" "$description" "$param_name" "$choices_csv" >"$out_xml" <<'PY'
import base64, html, sys
script = base64.b64decode(sys.argv[1]).decode()
desc = sys.argv[2]
param = sys.argv[3]
choices = [c.strip() for c in sys.argv[4].split(",") if c.strip()]
esc = html.escape(script)
desc_esc = html.escape(desc.encode("ascii", "replace").decode("ascii"))
strings = "\n".join(f"              <string>{html.escape(c)}</string>" for c in choices)
print(f"""<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>{desc_esc}</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>{html.escape(param)}</name>
          <description></description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
{strings}
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>{esc}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
""")
PY
  post_job_xml "$job_name" "$out_xml"
}

echo "==> Removing retired jobs (housekeeper + github poller)"
delete_job "housekeeper-stack"
delete_job "housekeeper-backend"
delete_job "housekeeper-frontend"
delete_job "watch-github"

SKIP_QUALITY_PARAM='<hudson.model.BooleanParameterDefinition>
          <name>SKIP_QUALITY</name>
          <description>Skip eslint/unit tests (emergency only)</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>'

sync_job "collaboration-stack" \
  "$JOBS_DIR/Jenkinsfile.collaboration-stack" \
  "Collaboration — start/stop the full stack, or trigger FE+BE image pipelines"

sync_job "collaboration-backend" \
  "$JOBS_DIR/Jenkinsfile.collaboration-backend" \
  "Collaboration backend — quality, image build/push, deploy, smoke" \
  "$SKIP_QUALITY_PARAM"

sync_job "collaboration-frontend" \
  "$JOBS_DIR/Jenkinsfile.collaboration-frontend" \
  "Collaboration frontend — quality, image build/push, deploy, smoke" \
  "$SKIP_QUALITY_PARAM"

sync_choice_job "pull-collaboration-now" \
  "$JOBS_DIR/Jenkinsfile.pull-collaboration-now" \
  "Pull Collaboration from GitHub NOW. Manual — no webhook required." \
  "TARGET" \
  "both,backend,frontend"

sync_choice_job "apply-vault-env" \
  "$JOBS_DIR/Jenkinsfile.apply-vault-env" \
  "Export Vault KV to collaboration/env/*.env then recreate/rebuild apps." \
  "TARGET" \
  "both,backend,frontend"

sync_choice_job "switch-watch-branch" \
  "$JOBS_DIR/Jenkinsfile.switch-watch-branch" \
  "Change which GitHub branch Collaboration FE/BE watch, then optionally rebuild." \
  "REPO" \
  "collaboration-backend,collaboration-frontend,collaboration-both"

sync_gwt_job "sync-devops-control-plane" \
  "$JOBS_DIR/Jenkinsfile.sync-devops-control-plane" \
  "GitHub push to DevOps repo → git pull /var/devops + sync-jobs.sh. Do not scp Jenkinsfiles." \
  "$SECRETS_DIR/github-webhook-token.txt"

sync_gwt_job "github-push-collaboration" \
  "$JOBS_DIR/Jenkinsfile.github-push-collaboration" \
  "GitHub push to Collaboration FE/BE → quality, image, deploy the changed app." \
  "$SECRETS_DIR/github-webhook-collab-token.txt"

rm -f "$COOKIE_JAR"
echo
echo "Done. Control-plane sync:"
echo "  Open Jenkins → sync-devops-control-plane (or push DevOps main)"
echo "Webhook URLs (replace TOKEN from jenkins/secrets/*.txt):"
echo "  .../generic-webhook-trigger/invoke?token=<devops-token>   → sync-devops-control-plane"
echo "  .../generic-webhook-trigger/invoke?token=<collab-token>   → github-push-collaboration"
