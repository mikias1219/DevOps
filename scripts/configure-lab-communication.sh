#!/usr/bin/env bash
# Patch lab env files so FE ↔ BE ↔ Notification communicate on SERVER_IP.
# Run before vault-import-from-env.sh (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-172.16.50.39}"

BE_ENV="$ROOT/collaboration/env/backend.env"
FE_ENV="$ROOT/collaboration/env/frontend.env"
NES_ENV="$ROOT/notification/env/notification.env"

set_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  [[ -f "$file" ]] || touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

log() { echo "==> $*"; }

log "Configuring inter-service URLs for ${SERVER_IP}"

if [[ -f "$BE_ENV" ]]; then
  set_kv "$BE_ENV" "APP_PUBLIC_BASE_URL" "http://${SERVER_IP}:5000"
  set_kv "$BE_ENV" "COLLABORATION_FRONT_URL" "http://${SERVER_IP}:3000"
  set_kv "$BE_ENV" "NOTIFICATION_SERVICE_URL" "http://${SERVER_IP}:8006/api/v1"
  set_kv "$BE_ENV" "NOTIFICATION_SERVICE_AUTH_TOKEN" "Bearer lab-notification-token"
  chmod 600 "$BE_ENV"
fi

if [[ -f "$FE_ENV" ]]; then
  set_kv "$FE_ENV" "NEXT_PUBLIC_APP_URL" "http://${SERVER_IP}:3000"
  set_kv "$FE_ENV" "NEXT_PUBLIC_API_URL" "http://${SERVER_IP}:5000/api/v1"
  set_kv "$FE_ENV" "NEXT_PUBLIC_API_BASE_URL" "http://${SERVER_IP}:5000/api/v1"
  set_kv "$FE_ENV" "NEXT_PUBLIC_COLLABORATION_URL" "http://${SERVER_IP}:5000/api/v1"
  set_kv "$FE_ENV" "NEXT_PUBLIC_WS_URL" "http://${SERVER_IP}:5000"
  set_kv "$FE_ENV" "NEXT_PUBLIC_COLLABORATION_SOCKET_URL" "http://${SERVER_IP}:5000"
  chmod 600 "$FE_ENV"
fi

if [[ -f "$NES_ENV" ]]; then
  set_kv "$NES_ENV" "APP_PORT" "8006"
  set_kv "$NES_ENV" "POSTGRES_HOST" "db"
  set_kv "$NES_ENV" "POSTGRES_PORT" "5432"
  set_kv "$NES_ENV" "COLLABORATION_SERVICE_URL" "http://${SERVER_IP}:5000/api/v1"
  set_kv "$NES_ENV" "NOTIFICATION_SERVICE_AUTH_TOKEN" "Bearer lab-notification-token"
  set_kv "$NES_ENV" "COLLABORATION_SERVICE_AUTH_TOKEN" "Bearer lab-collaboration-token"
  chmod 600 "$NES_ENV"
fi

log "Done. Import into Vault: bash scripts/vault-import-all-env.sh"
