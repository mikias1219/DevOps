#!/usr/bin/env bash
# Import backend, frontend, compose, and notification env files into Vault KV.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-172.16.50.39}"

bash "$ROOT/scripts/configure-lab-communication.sh"

# Ensure vault is up and unsealed
docker compose -f "$ROOT/vault/docker-compose.yml" up -d
sleep 2
if [[ -f "$ROOT/vault/secrets/vault-keys.env" ]]; then
  # shellcheck disable=SC1091
  set -a; . "$ROOT/vault/secrets/vault-keys.env"; set +a
  if docker exec selamnew-vault vault status -format=json 2>/dev/null | grep -q '"sealed":true'; then
    docker exec selamnew-vault vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null 2>&1 || true
  fi
fi

# Re-bootstrap if vault was never initialized (fresh volume)
if docker exec selamnew-vault vault status 2>&1 | grep -q 'Initialized.*false'; then
  echo "==> Vault not initialized — running bootstrap"
  rm -f "$ROOT/vault/secrets/vault-keys.env" "$ROOT/vault/secrets/vault-approle.env"
  bash "$ROOT/vault/scripts/bootstrap.sh"
fi

bash "$ROOT/scripts/vault-import-from-env.sh" \
  "$ROOT/collaboration/env/backend.env" \
  "$ROOT/collaboration/env/frontend.env" \
  "$ROOT/collaboration/.env.docker"

# Notification path (added to import script via fourth call)
bash "$ROOT/scripts/vault-import-one.sh" \
  "collaboration/notification" \
  "$ROOT/notification/env/notification.env"

echo "==> Export to disk"
bash "$ROOT/scripts/vault-export-all-env.sh"

echo "Vault import complete for backend, frontend, compose, notification."
