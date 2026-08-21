#!/usr/bin/env bash
# Import collaboration/env/*.env into Vault KV (one-time seed).
# Paths: secret/collaboration/backend | frontend | compose (.env.docker)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$ROOT/vault/secrets"
BACKEND_ENV="${1:-$ROOT/collaboration/env/backend.env}"
FRONTEND_ENV="${2:-$ROOT/collaboration/env/frontend.env}"
COMPOSE_ENV="${3:-$ROOT/collaboration/.env.docker}"

if [[ -f "$SECRETS_DIR/vault-keys.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/vault-keys.env"
  set +a
  export VAULT_TOKEN="${VAULT_ROOT_TOKEN:?}"
elif [[ -f "$SECRETS_DIR/vault-approle.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/vault-approle.env"
  set +a
else
  echo "Need vault/secrets/vault-keys.env (or approle). Run vault/scripts/bootstrap.sh first." >&2
  exit 1
fi

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

if ! command -v vault >/dev/null 2>&1; then
  if [[ -x /tmp/vault ]]; then
    VAULT_BIN=/tmp/vault
  else
    echo "vault CLI not found" >&2
    exit 1
  fi
else
  VAULT_BIN="$(command -v vault)"
fi

# If only Approle creds, login
if [[ -z "${VAULT_TOKEN:-}" && -n "${VAULT_ROLE_ID:-}" ]]; then
  VAULT_TOKEN="$("$VAULT_BIN" write -field=token auth/approle/login \
    role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
  export VAULT_TOKEN
fi

env_to_kv_args() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys
path = sys.argv[1]
args = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        v = v.strip().strip('"').strip("'")
        if not k:
            continue
        # vault kv put KEY=VALUE — escape via separate argv later
        print(f"{k}={v}")
PY
}

put_env_file() {
  local mount_path="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo "SKIP missing $file"
    return 0
  fi
  echo "==> Import $file → secret/$mount_path"
  mapfile -t PAIRS < <(env_to_kv_args "$file")
  if [[ ${#PAIRS[@]} -eq 0 ]]; then
    echo "  (empty)"
    return 0
  fi
  "$VAULT_BIN" kv put "secret/${mount_path}" "${PAIRS[@]}"
}

put_env_file "collaboration/backend" "$BACKEND_ENV"
put_env_file "collaboration/frontend" "$FRONTEND_ENV"
put_env_file "collaboration/compose" "$COMPOSE_ENV"

echo "Import done. Export later with: ./scripts/vault-export-collaboration-env.sh"
