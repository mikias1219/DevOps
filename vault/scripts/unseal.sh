#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
set -a; . "$ROOT/secrets/vault-keys.env"; set +a
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 selamnew-vault vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null
