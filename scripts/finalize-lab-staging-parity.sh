#!/usr/bin/env bash
# One-shot: sync lab config, Jenkins jobs, nginx, env URLs, optional redeploy.
# Run ON the lab server from docker-devops root (after rsync/git pull of DevOps).
#
#   cd /home/ienetworks/workspace/tools/docker-devops
#   bash scripts/finalize-lab-staging-parity.sh
#
# From laptop (VPN):  ./scripts/install-from-laptop.sh --skip-build  then SSH and run this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SERVER_IP="${SERVER_IP:-172.16.50.39}"

log() { echo "==> $*"; }

log "Patch inter-service URLs (nginx :80, same as staging test URLs pattern)"
bash "$ROOT/scripts/configure-lab-communication.sh"

log "Vault unseal + import env (if Vault available)"
bash "$ROOT/scripts/ensure-vault-unsealed.sh" 2>/dev/null || true
bash "$ROOT/scripts/vault-import-from-env.sh" 2>/dev/null || true

log "Install nginx front door"
if [ -f "$ROOT/nginx/selamnew-collab.conf" ]; then
  sudo cp "$ROOT/nginx/selamnew-collab.conf" /etc/nginx/sites-available/selamnew-collab
  sudo ln -sfn /etc/nginx/sites-available/selamnew-collab /etc/nginx/sites-enabled/selamnew-collab
  sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/selamnew-devops-webhooks 2>/dev/null || true
  sudo nginx -t
  sudo systemctl reload nginx
fi

log "Sync Jenkins jobs from DevOps/jenkins/jobs (production stage parity)"
if [ -f "$ROOT/jenkins/secrets/admin.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/jenkins/secrets/admin.env"
  set +a
fi
export JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
bash "$ROOT/jenkins/bin/sync-jobs.sh"

log "Ensure core infra"
docker compose -f "$ROOT/registry/docker-compose.yml" up -d
docker compose -f "$ROOT/collaboration/docker-compose.yml" --env-file "$ROOT/collaboration/.env.docker" \
  up -d db redis elasticsearch 2>/dev/null || true
docker compose -f "$ROOT/notification/docker-compose.yml" --env-file "$ROOT/notification/.env.docker" \
  up -d db 2>/dev/null || true

log "Verify (read-only)"
bash "$ROOT/scripts/verify-lab-staging-parity.sh"

echo
echo "Optional: redeploy all three apps like a develop push (runs full pipeline stages):"
echo "  bash jenkins/bin/trigger-build.sh collaboration-backend update-from-github"
echo "  bash jenkins/bin/trigger-build.sh collaboration-frontend update-from-github"
echo "  bash jenkins/bin/trigger-build.sh collaboration-notification update-from-github"
echo
echo "GitHub webhooks (each app repo, event push, branch develop):"
echo "  http://${SERVER_IP}/generic-webhook-trigger/invoke?token=\$(cat jenkins/secrets/github-webhook-collab-token.txt)"
