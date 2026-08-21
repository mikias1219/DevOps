#!/usr/bin/env bash
# One-shot bootstrap on the Ubuntu server after cloning DevOps.
# Does NOT print secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Jenkins admin secret"
mkdir -p "$ROOT/jenkins/secrets"
chmod 700 "$ROOT/jenkins/secrets"
if [[ ! -f "$ROOT/jenkins/secrets/admin.env" ]]; then
  cp "$ROOT/jenkins/secrets/admin.env.example" "$ROOT/jenkins/secrets/admin.env"
  echo "Edit jenkins/secrets/admin.env with a strong password, then re-run."
fi
if [[ ! -f "$ROOT/jenkins/secrets/github-webhook-token.txt" ]]; then
  openssl rand -hex 16 >"$ROOT/jenkins/secrets/github-webhook-token.txt"
  chmod 600 "$ROOT/jenkins/secrets/github-webhook-token.txt"
  echo "Wrote devops webhook token file"
fi
if [[ ! -f "$ROOT/jenkins/secrets/github-webhook-collab-token.txt" ]]; then
  # keep prior token name if you already used selamnew-collab-push
  echo -n "selamnew-collab-push" >"$ROOT/jenkins/secrets/github-webhook-collab-token.txt"
  chmod 600 "$ROOT/jenkins/secrets/github-webhook-collab-token.txt"
fi

echo "==> Start Vault"
docker compose -f "$ROOT/vault/docker-compose.yml" up -d
sleep 3
"$ROOT/vault/scripts/bootstrap.sh"

echo "==> Import existing env files into Vault (if present)"
if [[ -f "$ROOT/collaboration/env/backend.env" ]]; then
  "$ROOT/scripts/vault-import-from-env.sh" || true
fi

echo "==> Secrets Room"
if [[ ! -f "$ROOT/secrets-room/.env" ]]; then
  cp "$ROOT/secrets-room/.env.example" "$ROOT/secrets-room/.env"
  # shellcheck disable=SC1091
  . "$ROOT/vault/secrets/vault-keys.env"
  # shellcheck disable=SC1091
  . "$ROOT/jenkins/secrets/admin.env"
  {
    echo "VAULT_ADDR=${VAULT_ADDR:-http://127.0.0.1:8200}"
    echo "VAULT_TOKEN=${VAULT_ROOT_TOKEN}"
    echo "ROOM_BASIC_USER=operator"
    echo "ROOM_BASIC_PASS=$(openssl rand -hex 8)"
    echo "JENKINS_URL=http://127.0.0.1:8080"
    echo "JENKINS_ADMIN_USER=${JENKINS_ADMIN_USER:-admin}"
    echo "JENKINS_ADMIN_PASS=${JENKINS_ADMIN_PASS}"
    echo "COLLABORATION_SOURCE=${COLLABORATION_SOURCE:-/home/ienetworks/workspace/company/SelamnewCollaboration}"
  } >"$ROOT/secrets-room/.env"
  chmod 600 "$ROOT/secrets-room/.env"
fi
docker compose -f "$ROOT/secrets-room/docker-compose.yml" up -d --build

echo "==> Sync Jenkins jobs"
export JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
"$ROOT/jenkins/sync-jobs.sh" || echo "WARN: start Jenkins first, then re-run sync-jobs.sh"

echo
echo "Done."
echo "  Vault UI:       http://SERVER_IP:8200/ui"
echo "  Secrets Room:   http://SERVER_IP:8300/"
echo "  Jenkins sync:   job sync-devops-control-plane"
echo "  Webhook tokens: jenkins/secrets/github-webhook-*.txt"
echo "  Operator login: vault/secrets/operator-login.txt"
