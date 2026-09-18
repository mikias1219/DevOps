#!/usr/bin/env bash
# Sync DevOps to lab server and run multi-env finalize + optional tier bootstrap.
# Requires: LAB_SSH_PASSWORD or SSH key for ienetworks@172.16.50.39
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="${SERVER:-172.16.50.39}"
SSH_USER="${SSH_USER:-ienetworks}"
REMOTE="${SSH_USER}@${SERVER}"
REMOTE_DEVOPS="${REMOTE_DEVOPS:-/home/${SSH_USER}/workspace/tools/docker-devops}"

log() { echo "==> $*"; }

ssh_cmd() {
  if [[ -n "${LAB_SSH_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$LAB_SSH_PASSWORD" ssh -o StrictHostKeyChecking=accept-new "$@"
  else
    ssh -o StrictHostKeyChecking=accept-new "$@"
  fi
}

rsync_cmd() {
  if [[ -n "${LAB_SSH_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$LAB_SSH_PASSWORD" rsync "$@"
  else
    rsync "$@"
  fi
}

if ! ping -c 1 -W 3 "$SERVER" >/dev/null 2>&1; then
  echo "Server $SERVER not reachable (VPN?)" >&2
  exit 1
fi

if ! ssh_cmd -o ConnectTimeout=15 -o BatchMode=yes "$REMOTE" true 2>/dev/null; then
  if [[ -z "${LAB_SSH_PASSWORD:-}" ]]; then
    echo "Set LAB_SSH_PASSWORD for password auth, or configure SSH keys for $REMOTE" >&2
    exit 1
  fi
fi

log "Rsync DevOps → ${REMOTE}:${REMOTE_DEVOPS}"
ssh_cmd "$REMOTE" "mkdir -p $(dirname "$REMOTE_DEVOPS")"
rsync_cmd -az \
  --exclude '.git/' \
  --exclude 'collaboration/.env.docker' \
  --exclude 'collaboration/.env.docker.staging' \
  --exclude 'collaboration/.env.docker.production' \
  --exclude 'collaboration/env/*.env' \
  --exclude 'collaboration/env/staging/' \
  --exclude 'collaboration/env/production/' \
  --exclude 'notification/.env.docker' \
  --exclude 'notification/.env.docker.staging' \
  --exclude 'notification/.env.docker.production' \
  --exclude 'notification/env/*.env' \
  --exclude 'notification/env/staging/' \
  --exclude 'notification/env/production/' \
  --exclude 'jenkins/secrets/admin.env' \
  --exclude 'jenkins/secrets/github-webhook*.txt' \
  --exclude 'vault/secrets/' \
  "$ROOT/" "${REMOTE}:${REMOTE_DEVOPS}/"

log "Remote: setup multi-env + finalize"
ssh_cmd "$REMOTE" "bash -s" <<REMOTE
set -euo pipefail
cd '${REMOTE_DEVOPS}'
export SERVER_IP='${SERVER}'
export SUDO_PASSWORD="\${LAB_SSH_PASSWORD:-${LAB_SSH_PASSWORD:-}}"
bash scripts/setup-lab-multi-env.sh
bash scripts/configure-lab-communication.sh
if [ -f jenkins/secrets/admin.env ]; then
  set -a
  # shellcheck disable=SC1091
  . jenkins/secrets/admin.env
  set +a
fi
export JENKINS_URL=http://127.0.0.1:8080
bash jenkins/bin/sync-jobs.sh
if [ -n "\${SUDO_PASSWORD}" ]; then
  echo "\${SUDO_PASSWORD}" | sudo -S cp nginx/selamnew-collab.conf /etc/nginx/sites-available/selamnew-collab
  echo "\${SUDO_PASSWORD}" | sudo -S ln -sfn /etc/nginx/sites-available/selamnew-collab /etc/nginx/sites-enabled/selamnew-collab
  echo "\${SUDO_PASSWORD}" | sudo -S rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/selamnew-devops-webhooks 2>/dev/null || true
  echo "\${SUDO_PASSWORD}" | sudo -S nginx -t
  echo "\${SUDO_PASSWORD}" | sudo -S systemctl reload nginx
else
  sudo cp nginx/selamnew-collab.conf /etc/nginx/sites-available/selamnew-collab
  sudo ln -sfn /etc/nginx/sites-available/selamnew-collab /etc/nginx/sites-enabled/selamnew-collab
  sudo nginx -t && sudo systemctl reload nginx
fi
docker compose -f registry/docker-compose.yml up -d
for tier in test staging production; do
  case "\$tier" in
    test)
      CF=collaboration/docker-compose.yml
      EF=collaboration/.env.docker
      NF=notification/docker-compose.yml
      NEF=notification/.env.docker
      ;;
    staging)
      CF=collaboration/docker-compose.staging.yml
      EF=collaboration/.env.docker.staging
      NF=notification/docker-compose.staging.yml
      NEF=notification/.env.docker.staging
      ;;
    production)
      CF=collaboration/docker-compose.production.yml
      EF=collaboration/.env.docker.production
      NF=notification/docker-compose.production.yml
      NEF=notification/.env.docker.production
      ;;
  esac
  [ -f "\$EF" ] || continue
  docker compose -f "\$CF" --env-file "\$EF" up -d db redis elasticsearch 2>/dev/null || \
    docker compose -f "\$CF" --env-file "\$EF" up -d db redis elasticsearch || true
  [ -f "\$NEF" ] && docker compose -f "\$NF" --env-file "\$NEF" up -d db 2>/dev/null || true
done
bash scripts/verify-lab-staging-parity.sh || true
echo DEPLOY_MULTI_ENV_DONE
REMOTE

log "Done. URLs:"
echo "  test:        http://${SERVER}/"
echo "  staging:     http://${SERVER}/staging/"
echo "  production:  http://${SERVER}/production/"
