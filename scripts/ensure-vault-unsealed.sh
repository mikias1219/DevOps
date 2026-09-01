#!/usr/bin/env bash
# Unseal Vault if sealed. Safe to call from Jenkins / export scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$ROOT/vault/secrets"
KEYS_FILE="${SECRETS_DIR}/vault-keys.env"

if [[ ! -f "$KEYS_FILE" ]]; then
  echo "FATAL: missing ${KEYS_FILE} — run vault/scripts/bootstrap.sh first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. "$KEYS_FILE"
set +a

if [[ -z "${VAULT_UNSEAL_KEY:-}" ]]; then
  echo "FATAL: VAULT_UNSEAL_KEY empty in ${KEYS_FILE}" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx selamnew-vault; then
  echo "==> Starting Vault container"
  docker compose -f "$ROOT/vault/docker-compose.yml" up -d
  sleep 3
fi

vault_status() {
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 selamnew-vault vault status -format=json 2>/dev/null || echo '{}'
}

STATUS_JSON="$(vault_status)"
SEALED="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("sealed", True))' <<<"$STATUS_JSON" 2>/dev/null || echo True)"
INITIALIZED="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("initialized", False))' <<<"$STATUS_JSON" 2>/dev/null || echo False)"

if [[ "$INITIALIZED" != "True" && "$INITIALIZED" != "true" ]]; then
  echo "FATAL: Vault is not initialized — run vault/scripts/bootstrap.sh" >&2
  exit 1
fi

if [[ "$SEALED" == "True" || "$SEALED" == "true" ]]; then
  echo "==> Vault is sealed — unsealing"
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 selamnew-vault \
    vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null
  echo "==> Vault unsealed"
else
  echo "==> Vault already unsealed"
fi

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_ROOT_TOKEN:-${VAULT_TOKEN:-}}"
