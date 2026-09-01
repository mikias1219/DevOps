#!/usr/bin/env bash
# Import a single env file into Vault KV: vault-import-one.sh <mount_path> <file>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_PATH="${1:?mount path e.g. collaboration/notification}"
ENV_FILE="${2:?env file path}"
SECRETS_DIR="$ROOT/vault/secrets"

if [[ -f "$SECRETS_DIR/vault-keys.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/vault-keys.env"
  set +a
  export VAULT_TOKEN="${VAULT_ROOT_TOKEN:?}"
fi
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

if docker ps --format '{{.Names}}' | grep -qx selamnew-vault; then
  vault_cmd() { docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="${VAULT_TOKEN}" selamnew-vault vault "$@"; }
elif command -v vault >/dev/null 2>&1; then
  vault_cmd() { vault "$@"; }
else
  echo "No vault CLI" >&2
  exit 1
fi

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }

mapfile -t PAIRS < <(python3 - "$ENV_FILE" <<'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        print(f"{k.strip()}={v.strip().strip(chr(34)).strip(chr(39))}")
PY
)

echo "==> Import $ENV_FILE → secret/$MOUNT_PATH (${#PAIRS[@]} keys)"
vault_cmd kv put "secret/${MOUNT_PATH}" "${PAIRS[@]}"
