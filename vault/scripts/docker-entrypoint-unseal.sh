#!/bin/sh
# Start Vault (foreground), auto-unseal in the background when keys exist.
set -eu

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_ADDR

(
  i=0
  while [ "$i" -lt 90 ]; do
    if vault status >/dev/null 2>&1 || vault status 2>&1 | grep -q Sealed; then
      KEYS_FILE="/vault/secrets/vault-keys.env"
      if [ -f "$KEYS_FILE" ]; then
        # shellcheck disable=SC1090
        . "$KEYS_FILE"
        if [ "${VAULT_UNSEAL_KEY:-}" != "" ]; then
          echo "Auto-unsealing Vault..."
          vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null || true
        fi
      else
        echo "No /vault/secrets/vault-keys.env yet — Vault may stay sealed until bootstrap."
      fi
      exit 0
    fi
    i=$((i + 1))
    sleep 1
  done
  echo "WARN: Vault API not ready for auto-unseal within timeout"
) &

if command -v docker-entrypoint.sh >/dev/null 2>&1; then
  exec docker-entrypoint.sh "$@"
fi
exec vault "$@"
