#!/usr/bin/env bash
# Unseal lab Vault after start/restart. Safe to run repeatedly.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
set -a
. "$ROOT/secrets/vault-keys.env"
set +a

echo "==> Waiting for Vault API..."
for _ in $(seq 1 40); do
  if docker exec -e VAULT_ADDR=http://127.0.0.1:8200 selamnew-vault \
    vault status -format=json >/tmp/vault-status.json 2>/dev/null; then
    break
  fi
  # sealed still returns non-zero sometimes — accept any HTTP response from health
  if curl -sf http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1 \
    || curl -sf "http://127.0.0.1:8200/v1/sys/health?sealedcode=200&uninitcode=200" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec -e VAULT_ADDR=http://127.0.0.1:8200 selamnew-vault \
  vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null

curl -sf http://127.0.0.1:8200/v1/sys/health | python3 -c \
  'import sys,json; d=json.load(sys.stdin); print("sealed="+str(d.get("sealed")), "initialized="+str(d.get("initialized")))'
