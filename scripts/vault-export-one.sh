#!/usr/bin/env bash
# Export one Vault KV path to an env file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_PATH="${1:?e.g. collaboration/notification}"
OUT_FILE="${2:?output env file}"
SECRETS_DIR="$ROOT/vault/secrets"
DEVOPS_HOST_PATH="${DEVOPS_HOST_PATH:-/home/ienetworks/workspace/tools/docker-devops}"

mkdir -p "$(dirname "$OUT_FILE")"

bash "$ROOT/scripts/ensure-vault-unsealed.sh"

if [[ -f "$SECRETS_DIR/vault-keys.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/vault-keys.env"
  set +a
  export VAULT_TOKEN="${VAULT_ROOT_TOKEN:-}"
fi
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

if docker ps --format '{{.Names}}' | grep -qx selamnew-vault; then
  vault_cmd() { docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="${VAULT_TOKEN}" selamnew-vault vault "$@"; }
else
  vault_cmd() { vault "$@"; }
fi

echo "==> Export secret/${MOUNT_PATH} → ${OUT_FILE}"
json="$(vault_cmd kv get -format=json "secret/${MOUNT_PATH}")"
OUT_FILE="$OUT_FILE" python3 -c '
import json, os, sys
out = os.environ["OUT_FILE"]
data = json.load(sys.stdin)
payload = (data.get("data") or {}).get("data") or {}
lines = [f"{k}={payload[k]}" for k in sorted(payload.keys()) if k != "_seed"]
with open(out, "w") as f:
    f.write("\n".join(lines) + ("\n" if lines else ""))
print(f"  wrote {len(lines)} keys")
' <<<"$json"
chmod 600 "$OUT_FILE" 2>/dev/null || true
