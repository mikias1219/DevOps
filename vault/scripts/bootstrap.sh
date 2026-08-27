#!/usr/bin/env bash
# First-time Vault init + KV enable + policies + userpass for Secrets Room / CI.
# Run on the host (or any machine with vault CLI + curl) against local Vault.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_DIR="$ROOT/vault/secrets"
COMPOSE="$ROOT/vault/docker-compose.yml"
ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_ADDR="$ADDR"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if ! command -v vault >/dev/null 2>&1; then
  echo "Installing vault CLI into /tmp for bootstrap..."
  curl -fsSL -o /tmp/vault.zip \
    https://releases.hashicorp.com/vault/1.17.6/vault_1.17.6_linux_amd64.zip
  unzip -o /tmp/vault.zip -d /tmp
  VAULT_BIN=/tmp/vault
else
  VAULT_BIN="$(command -v vault)"
fi

echo "==> Waiting for Vault at $ADDR"
for _ in $(seq 1 40); do
  if curl -sf "$ADDR/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" >/dev/null 2>&1 \
    || curl -sf "$ADDR/v1/sys/health?standbyok=true" >/dev/null 2>&1 \
    || curl -s "$ADDR/v1/sys/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

STATUS_JSON="$("$VAULT_BIN" status -format=json 2>/dev/null || echo '{}')"
INITIALIZED="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("initialized", False))' <<<"$STATUS_JSON" 2>/dev/null || echo False)"

if [[ "$INITIALIZED" != "True" && "$INITIALIZED" != "true" ]]; then
  echo "==> Initializing Vault (1 key share)"
  INIT_OUT="$("$VAULT_BIN" operator init -key-shares=1 -key-threshold=1 -format=json)"
  UNSEAL="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["unseal_keys_b64"][0])' <<<"$INIT_OUT")"
  ROOT_TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["root_token"])' <<<"$INIT_OUT")"
  umask 077
  cat >"$SECRETS_DIR/vault-keys.env" <<EOF
VAULT_UNSEAL_KEY=${UNSEAL}
VAULT_ROOT_TOKEN=${ROOT_TOKEN}
VAULT_ADDR=${ADDR}
EOF
  chmod 600 "$SECRETS_DIR/vault-keys.env"
  echo "Wrote $SECRETS_DIR/vault-keys.env"
  "$VAULT_BIN" operator unseal "$UNSEAL" >/dev/null
else
  echo "==> Already initialized"
  if [[ -f "$SECRETS_DIR/vault-keys.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    . "$SECRETS_DIR/vault-keys.env"
    set +a
  else
    echo "FATAL: Vault initialized but vault/secrets/vault-keys.env missing" >&2
    exit 1
  fi
  if [[ "${VAULT_UNSEAL_KEY:-}" != "" ]]; then
    "$VAULT_BIN" operator unseal "$VAULT_UNSEAL_KEY" >/dev/null || true
  fi
fi

set -a
# shellcheck disable=SC1091
. "$SECRETS_DIR/vault-keys.env"
set +a
export VAULT_TOKEN="$VAULT_ROOT_TOKEN"

echo "==> Enable KV v2 at secret/"
"$VAULT_BIN" secrets enable -path=secret kv-v2 2>/dev/null || echo "KV already enabled"

echo "==> Write collaboration policies"
"$VAULT_BIN" policy write collaboration-admin - <<'EOF'
path "secret/metadata/" {
  capabilities = ["list"]
}
path "secret/metadata/collaboration" {
  capabilities = ["list"]
}
path "secret/metadata/collaboration/" {
  capabilities = ["list"]
}
path "secret/data/collaboration/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "secret/metadata/collaboration/*" {
  capabilities = ["list", "read", "update", "delete"]
}
EOF

OPERATOR_PASS="${VAULT_OPERATOR_PASSWORD:-$(openssl rand -hex 12)}"
"$VAULT_BIN" auth enable userpass 2>/dev/null || true
"$VAULT_BIN" write auth/userpass/users/operator \
  password="$OPERATOR_PASS" \
  policies=collaboration-admin

# AppRole for CI / export scripts
"$VAULT_BIN" auth enable approle 2>/dev/null || true
"$VAULT_BIN" policy write collaboration-reader - <<'EOF'
path "secret/data/collaboration/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/collaboration/*" {
  capabilities = ["list", "read"]
}
EOF
"$VAULT_BIN" write auth/approle/role/collaboration-export \
  token_policies="collaboration-reader" \
  token_ttl=1h \
  token_max_ttl=4h

ROLE_ID="$("$VAULT_BIN" read -field=role_id auth/approle/role/collaboration-export/role-id)"
SECRET_ID="$("$VAULT_BIN" write -field=secret_id -f auth/approle/role/collaboration-export/secret-id)"

umask 077
cat >"$SECRETS_DIR/vault-approle.env" <<EOF
VAULT_ADDR=${ADDR}
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${SECRET_ID}
EOF
chmod 600 "$SECRETS_DIR/vault-approle.env"

# Seed empty paths so UI lists them
"$VAULT_BIN" kv put secret/collaboration/backend _seed=true >/dev/null || true
"$VAULT_BIN" kv put secret/collaboration/frontend _seed=true >/dev/null || true
"$VAULT_BIN" kv put secret/collaboration/compose _seed=true >/dev/null || true

cat >"$SECRETS_DIR/operator-login.txt" <<EOF
Vault UI:  ${ADDR}/ui
User:      operator
Password:  ${OPERATOR_PASS}
Root token is in vault-keys.env (keep offline / chmod 600)
AppRole:   vault-approle.env (for export scripts)
EOF
chmod 600 "$SECRETS_DIR/operator-login.txt"

echo
echo "Bootstrap complete."
echo "  UI:        $ADDR/ui"
echo "  Operator:  see $SECRETS_DIR/operator-login.txt"
echo "  Next:      ./scripts/vault-import-from-env.sh"
