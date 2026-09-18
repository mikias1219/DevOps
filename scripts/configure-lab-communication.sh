#!/usr/bin/env bash
# Patch tier env files so FE ↔ BE ↔ NES use nginx path URLs for each lab tier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-172.16.50.39}"
LAB_TIER="${LAB_TIER:-all}"

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

patch_tier() {
  local tier="$1"
  local base
  case "$tier" in
    staging) base="http://${SERVER_IP}/staging" ;;
    production) base="http://${SERVER_IP}/production" ;;
    *) base="http://${SERVER_IP}" ;;
  esac

  local be_env fe_env nes_env
  if [ "$tier" = test ]; then
    be_env="$ROOT/collaboration/env/backend.env"
    fe_env="$ROOT/collaboration/env/frontend.env"
    nes_env="$ROOT/notification/env/notification.env"
  else
    be_env="$ROOT/collaboration/env/${tier}/backend.env"
    fe_env="$ROOT/collaboration/env/${tier}/frontend.env"
    nes_env="$ROOT/notification/env/${tier}/notification.env"
  fi

  echo "==> URLs for tier=${tier} base=${base}"

  if [[ -f "$be_env" ]]; then
    set_kv "$be_env" "APP_PUBLIC_BASE_URL" "${base}"
    set_kv "$be_env" "COLLABORATION_FRONT_URL" "${base}"
    set_kv "$be_env" "NOTIFICATION_SERVICE_URL" "${base}/notification/api/v1"
    chmod 600 "$be_env"
  fi

  if [[ -f "$fe_env" ]]; then
    set_kv "$fe_env" "NEXT_PUBLIC_APP_URL" "${base}"
    set_kv "$fe_env" "NEXT_PUBLIC_APP_BASE_URL" "${base}"
    set_kv "$fe_env" "NEXT_PUBLIC_API_URL" "${base}/api/v1"
    set_kv "$fe_env" "NEXT_PUBLIC_API_BASE_URL" "${base}/api/v1"
    set_kv "$fe_env" "NEXT_PUBLIC_COLLABORATION_URL" "${base}/api/v1"
    set_kv "$fe_env" "NEXT_PUBLIC_WS_URL" "${base}"
    set_kv "$fe_env" "NEXT_PUBLIC_COLLABORATION_SOCKET_URL" "${base}"
    set_kv "$fe_env" "NEXT_PUBLIC_NOTIFICATION_URL" "${base}/notification/api/v1"
    chmod 600 "$fe_env"
  fi

  if [[ -f "$nes_env" ]]; then
    set_kv "$nes_env" "COLLABORATION_SERVICE_URL" "${base}/api/v1"
    set_kv "$nes_env" "FILE_SERVER_URL" "${base}"
    chmod 600 "$nes_env"
  fi
}

case "$LAB_TIER" in
  all)
    patch_tier test
    patch_tier staging
    patch_tier production
    ;;
  test|staging|production)
    patch_tier "$LAB_TIER"
    ;;
  *)
    echo "LAB_TIER must be test|staging|production|all" >&2
    exit 1
    ;;
esac

echo "Done."
