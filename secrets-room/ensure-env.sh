#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env"
  echo "Created secrets-room/.env — fill VAULT_TOKEN and JENKINS_ADMIN_PASS from vault/jenkins secrets."
else
  echo ".env already present"
fi
