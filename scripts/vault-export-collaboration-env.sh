#!/usr/bin/env bash
# Export Vault KV → collaboration/env/{backend,frontend}.env (chmod 600).
# TARGET=both|backend|frontend (default both)
# Jenkins has no python3 — uses secrets-room Node, then python container.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$ROOT/vault/secrets"
OUT_DIR="$ROOT/collaboration/env"
TARGET="${TARGET:-both}"
DEVOPS_HOST_PATH="${DEVOPS_HOST_PATH:-/home/ienetworks/workspace/tools/docker-devops}"

mkdir -p "$OUT_DIR"

# Jenkins / host: Vault seals on container restart — unseal before any KV read.
bash "$ROOT/scripts/ensure-vault-unsealed.sh"

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

# Path as seen inside Jenkins/secrets-room (/var/devops/...)
to_container_devops_path() {
  local p="$1"
  if [[ "$p" == /var/devops/* ]]; then
    printf '%s\n' "$p"
  elif [[ "$p" == "$DEVOPS_HOST_PATH"/* ]]; then
    printf '/var/devops%s\n' "${p#"$DEVOPS_HOST_PATH"}"
  elif [[ "$p" == "$ROOT"/* && "$ROOT" != /var/devops ]]; then
    # ROOT is host checkout path
    printf '/var/devops%s\n' "${p#"$ROOT"}"
  else
    printf '%s\n' "$p"
  fi
}

to_host_path() {
  local p="$1"
  if [[ "$p" == /var/devops/* ]]; then
    printf '%s%s\n' "$DEVOPS_HOST_PATH" "${p#/var/devops}"
  else
    printf '%s\n' "$p"
  fi
}

write_env_from_json() {
  local out_file="$1"
  local json="$2"
  local c_out host_out
  c_out="$(to_container_devops_path "$out_file")"
  host_out="$(to_host_path "$c_out")"

  # Ensure dir exists in *this* filesystem (Jenkins bind-mounts /var/devops)
  mkdir -p "$(dirname "$out_file")"

  local py_script='
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
'

  if command -v python3 >/dev/null 2>&1; then
    OUT_FILE="$out_file" python3 -c "$py_script" <<<"$json"
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx selamnew-secrets-room; then
    # secrets-room mounts ..:/var/devops — write there, never mkdir host paths from Jenkins
    printf '%s' "$json" | docker exec -i -e OUT_FILE="$c_out" selamnew-secrets-room \
      node -e '
const fs = require("fs");
let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  const data = JSON.parse(raw);
  const payload = (data.data && data.data.data) || data.data || {};
  const lines = Object.keys(payload)
    .filter((k) => k !== "_seed")
    .sort()
    .map((k) => k + "=" + (payload[k] == null ? "" : String(payload[k])));
  fs.mkdirSync(require("path").dirname(process.env.OUT_FILE), { recursive: true });
  fs.writeFileSync(process.env.OUT_FILE, lines.join("\n") + (lines.length ? "\n" : ""));
  console.log("  wrote " + lines.length + " keys");
});
'
  else
    printf '%s' "$json" | docker run --rm -i \
      -v "$(dirname "$host_out"):/out" \
      -e OUT_FILE="/out/$(basename "$host_out")" \
      python:3.12-bookworm \
      python3 -c "$py_script"
  fi

  chmod 600 "$out_file" 2>/dev/null || true
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
