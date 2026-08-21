#!/usr/bin/env bash
# Export Vault KV → collaboration/env/{backend,frontend}.env (chmod 600).
# TARGET=both|backend|frontend (default both)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$ROOT/vault/secrets"
OUT_DIR="$ROOT/collaboration/env"
TARGET="${TARGET:-both}"

mkdir -p "$OUT_DIR"

if [[ -f "$SECRETS_DIR/vault-keys.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/vault-keys.env"
  set +a
  export VAULT_TOKEN="${VAULT_ROOT_TOKEN:-${VAULT_TOKEN:-}}"
fi
if [[ -z "${VAULT_TOKEN:-}" && -f "$SECRETS_DIR/vault-approle.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SECRETS_DIR/vault-approle.env"
  set +a
fi

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

use_docker_vault=0
# Prefer Vault container (works from Jenkins/Secrets Room where 127.0.0.1 is not the host).
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx selamnew-vault; then
  use_docker_vault=1
elif command -v vault >/dev/null 2>&1; then
  VAULT_BIN="$(command -v vault)"
elif [[ -x /tmp/vault ]]; then
  VAULT_BIN=/tmp/vault
else
  echo "vault CLI not found and vault container not running" >&2
  exit 1
fi

vault_cmd() {
  if [[ "$use_docker_vault" -eq 1 ]]; then
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="${VAULT_TOKEN:-}" \
      selamnew-vault vault "$@"
  else
    "$VAULT_BIN" "$@"
  fi
}

if [[ -z "${VAULT_TOKEN:-}" && -n "${VAULT_ROLE_ID:-}" ]]; then
  VAULT_TOKEN="$(vault_cmd write -field=token auth/approle/login \
    role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
  export VAULT_TOKEN
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  echo "No VAULT_TOKEN — set vault-keys.env or vault-approle.env" >&2
  exit 1
fi

write_env_from_json() {
  local out_file="$1"
  local json="$2"
  umask 077
  OUT_FILE="$out_file" python3 -c '
import json, os, sys
out = os.environ["OUT_FILE"]
data = json.load(sys.stdin)
payload = data.get("data", {}).get("data") or data.get("data") or {}
lines = []
for k in sorted(payload.keys()):
    if k == "_seed":
        continue
    v = payload[k]
    if v is None:
        v = ""
    lines.append(f"{k}={v}")
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + ("\n" if lines else ""))
print(f"  wrote {len(lines)} keys")
' <<<"$json"
  chmod 600 "$out_file"
}

export_path() {
  local mount_path="$1"
  local out_file="$2"
  echo "==> Export secret/${mount_path} → $out_file"
  local json
  json="$(vault_cmd kv get -format=json "secret/${mount_path}")"
  write_env_from_json "$out_file" "$json"
}

case "$TARGET" in
  backend)
    export_path "collaboration/backend" "$OUT_DIR/backend.env"
    ;;
  frontend)
    export_path "collaboration/frontend" "$OUT_DIR/frontend.env"
    ;;
  both)
    export_path "collaboration/backend" "$OUT_DIR/backend.env"
    export_path "collaboration/frontend" "$OUT_DIR/frontend.env"
    if vault_cmd kv get "secret/collaboration/compose" >/dev/null 2>&1; then
      export_path "collaboration/compose" "$ROOT/collaboration/.env.docker" || true
    fi
    ;;
  *)
    echo "TARGET must be both|backend|frontend" >&2
    exit 1
    ;;
esac

echo "Export done."
