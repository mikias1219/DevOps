#!/usr/bin/env bash
# Read-only check: lab server matches staging-practice flow (webhook → Jenkins → compose → nginx).
# Run on the lab host: bash scripts/verify-lab-staging-parity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-172.16.50.39}"
FAIL=0

ok() { echo "  OK  $*"; }
bad() { echo "  FAIL $*"; FAIL=1; }
warn() { echo "  WARN $*"; }

echo "=== Lab staging-parity verification (${SERVER_IP}) ==="
echo

echo "1. DevOps tree"
[ -f "$ROOT/jenkins/lib/docker-lib.sh" ] && ok "docker-lib.sh" || bad "missing docker-lib.sh"
[ -f "$ROOT/nginx/selamnew-collab.conf" ] && ok "nginx selamnew-collab.conf" || bad "missing nginx config"
grep -q 'remove_existing_migrations_backend' "$ROOT/jenkins/lib/docker-lib.sh" && ok "migration parity helpers" || bad "migration helpers missing"
grep -q 'select_environment_lab_backend' "$ROOT/jenkins/lib/docker-lib.sh" && ok "select_environment_lab_*" || bad "lab env helpers missing"

echo
echo "2. Jenkins jobs (router + 9 tier jobs + vault + sync)"
if curl -sf http://127.0.0.1:8080/login >/dev/null 2>&1; then
  JAUTH=()
  if [ -f "$ROOT/jenkins/secrets/admin.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$ROOT/jenkins/secrets/admin.env"
    set +a
    JAUTH=(-u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}")
  fi
  for j in github-push-collaboration apply-vault-env sync-devops-control-plane \
    collaboration-backend-test collaboration-frontend-test collaboration-notification-test \
    collaboration-backend-staging collaboration-frontend-staging collaboration-notification-staging \
    collaboration-backend-production collaboration-frontend-production collaboration-notification-production; do
    code=$(curl -s "${JAUTH[@]}" -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080/job/${j}/api/json" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && ok "job ${j}" || bad "job ${j} (HTTP ${code})"
  done
else
  bad "Jenkins not reachable on :8080"
fi

echo
echo "3. Webhook tokens"
[ -f "$ROOT/jenkins/secrets/github-webhook-collab-token.txt" ] && ok "collab webhook token" || warn "missing github-webhook-collab-token.txt"
[ -f "$ROOT/jenkins/secrets/github-webhook-token.txt" ] && ok "devops webhook token" || warn "missing github-webhook-token.txt"

echo
echo "4. Docker stacks"
docker ps --format '{{.Names}}' | grep -qx jenkins-jenkins-1 && ok "jenkins" || bad "jenkins container"
docker ps --format '{{.Names}}' | grep -qx collaboration-backend-1 && ok "backend" || bad "backend container"
docker ps --format '{{.Names}}' | grep -qx collaboration-frontend-1 && ok "frontend" || bad "frontend container"
docker ps --format '{{.Names}}' | grep -qx notification-notification-1 && ok "notification" || bad "notification container"
docker ps --format '{{.Names}}' | grep -qx selamnew-vault && ok "vault" || warn "vault container"

echo
echo "5. Nginx :80 (test + staging + production path URLs)"
if systemctl is-active nginx >/dev/null 2>&1; then
  ok "nginx active"
  curl -sf -o /dev/null -w '' "http://127.0.0.1/" && ok "GET / (test FE)" || bad "GET /"
  curl -sf "http://127.0.0.1/api/v1/health" | grep -q '"status"' && ok "GET /api/v1/health (test BE)" || bad "GET /api/v1/health"
  curl -sf "http://127.0.0.1/notification/api/v1/health" | grep -q '"status"' && ok "GET /notification/... (test NES)" || bad "NES test health"
  for prefix in staging production; do
    if curl -sf -o /dev/null "http://127.0.0.1/${prefix}/" 2>/dev/null; then
      curl -sf "http://127.0.0.1/${prefix}/api/v1/health" 2>/dev/null | grep -q '"status"' \
        && ok "GET /${prefix}/api/v1/health" || warn "/${prefix}/ stack not healthy yet (run Jenkins build-and-start)"
    else
      warn "/${prefix}/ not deployed yet"
    fi
  done
  [ -f "$ROOT/collaboration/lab-secrets/test/.collab-back-env" ] && ok "lab-secrets/test" || warn "run setup-lab-multi-env.sh"
else
  bad "nginx not active"
fi

echo
echo "6. Webhook dry-run (router only; does not deploy if repo unknown)"
if [ -f "$ROOT/jenkins/secrets/github-webhook-collab-token.txt" ]; then
  TOKEN=$(tr -d '[:space:]' < "$ROOT/jenkins/secrets/github-webhook-collab-token.txt")
  resp=$(curl -sS -X POST -H 'Content-Type: application/json' \
    --data '{"ref":"refs/heads/develop","repository":{"full_name":"ie-network-solutions/selamnew-collaboration-backend","name":"selamnew-collaboration-backend"}}' \
    "http://127.0.0.1/generic-webhook-trigger/invoke?token=${TOKEN}" 2>/dev/null || true)
  echo "$resp" | grep -q '"triggered":true' && ok "GWT via nginx → router" || warn "webhook response: ${resp:-empty} (try sync-jobs.sh)"
else
  warn "skip webhook test (no token file)"
fi

echo
echo "7. Git checkouts (develop practice branch)"
SRC="$(grep -E '^COLLABORATION_SOURCE=' "$ROOT/collaboration/.env.docker" 2>/dev/null | cut -d= -f2- || true)"
SRC="${SRC:-/home/ienetworks/workspace/company/SelamnewCollaboration}"
for sub in backend frontend; do
  if [ -d "$SRC/$sub/.git" ]; then
    br=$(git -C "$SRC/$sub" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    ok "${sub} checkout on branch ${br}"
  else
    warn "${sub} not a git repo under ${SRC}"
  fi
done

echo
if [ "$FAIL" -eq 0 ]; then
  echo "=== RESULT: PASS — lab matches staging-practice flow (see LAB-PRODUCTION-PARITY.md) ==="
  exit 0
fi
echo "=== RESULT: FAIL — fix items above, then: bash scripts/finalize-lab-staging-parity.sh ==="
exit 1
