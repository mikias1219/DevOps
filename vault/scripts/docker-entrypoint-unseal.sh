#!/bin/sh
# Start Vault server, then auto-unseal when keys file is present.
set -eu

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_ADDR

# Launch vault in background (official image entrypoint)
if command -v docker-entrypoint.sh >/dev/null 2>&1; then
  docker-entrypoint.sh "$@" &
else
  vault "$@" &
fi
VAULT_PID=$!

# Wait for vault process to answer (sealed or unsealed)
i=0
while [ "$i" -lt 60 ]; do
  if vault status >/dev/null 2>&1 || vault status 2>&1 | grep -q 'Sealed'; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

KEYS_FILE="/vault/secrets/vault-keys.env"
if [ -f "$KEYS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$KEYS_FILE"
  if [ "${VAULT_UNSEAL_KEY:-}" != "" ]; then
    echo "Auto-unsealing Vault..."
    vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null || true
  fi
else
  echo "No /vault/secrets/vault-keys.env yet — Vault may be sealed until bootstrap."
fi

wait "$VAULT_PID"
