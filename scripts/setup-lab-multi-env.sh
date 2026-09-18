#!/usr/bin/env bash
# Initialize test | staging | production tiers on the lab server (dirs, secrets templates, env files).
# Run from DevOps root on 172.16.50.39 after git pull/rsync.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_IP="${SERVER_IP:-172.16.50.39}"
PARENT="${COLLAB_PARENT:-/home/ienetworks/workspace/company/SelamnewCollaboration}"

log() { echo "==> $*"; }

tier_base() {
  case "$1" in
    test) printf '%s' "http://${SERVER_IP}" ;;
    staging) printf '%s' "http://${SERVER_IP}/staging" ;;
    production) printf '%s' "http://${SERVER_IP}/production" ;;
  esac
}

tier_branch() {
  case "$1" in
    staging) printf 'staging' ;;
    production) printf 'production' ;;
    *) printf 'develop' ;;
  esac
}

mkdir -p "$PARENT/environments/test" "$PARENT/environments/staging" "$PARENT/environments/production"
mkdir -p "$ROOT/collaboration/env/staging" "$ROOT/collaboration/env/production"
mkdir -p "$ROOT/collaboration/lab-secrets/test" "$ROOT/collaboration/lab-secrets/staging" "$ROOT/collaboration/lab-secrets/production"
mkdir -p "$ROOT/notification/env/staging" "$ROOT/notification/env/production"

for tier in test staging production; do
  _branch="$(tier_branch "$tier")"
  _base="$(tier_base "$tier")"
  _env_root="$PARENT/environments/$tier"

  for app in backend frontend Notification-and-email-service; do
    case "$app" in
      backend)
        _gh='git@github.com:ie-network-solutions/selamnew-collaboration-backend.git'
        _svc=backend
        _secret="$ROOT/collaboration/lab-secrets/${tier}/.collab-back-env"
        ;;
      frontend)
        _gh='git@github.com:ie-network-solutions/selamnew-collaboration-fe.git'
        _svc=frontend
        _secret="$ROOT/collaboration/lab-secrets/${tier}/.collab-fe-env"
        ;;
      *)
        _gh='git@github.com:ie-network-solutions/notification-and-email-service.git'
        _svc=notification
        _secret="$ROOT/collaboration/lab-secrets/${tier}/.collab-nes-env"
        ;;
    esac
    _dir="$_env_root/$app"
    if [ ! -f "$_secret" ]; then
      cat >"$_secret" <<EOF
REPO_URL=${_gh}
BRANCH_NAME=${_branch}
REPO_DIR=${_dir}
DOCKERHUB_REPO=127.0.0.1:5001/collaboration-${_svc}
SERVICE_NAME=${_svc}
VAULT_ADDR=http://127.0.0.1:8200
VAULT_SECRET_PATH=secret/collaboration/${tier}/${_svc}
EOF
      chmod 600 "$_secret"
      log "Created $_secret"
    fi
  done

  if [ "$tier" = test ]; then
    [ -f "$ROOT/collaboration/.env.docker" ] || cp "$ROOT/collaboration/.env.docker.example" "$ROOT/collaboration/.env.docker"
    sed -i "s|^COLLABORATION_SOURCE=.*|COLLABORATION_SOURCE=${_env_root}|" "$ROOT/collaboration/.env.docker" 2>/dev/null || true
    grep -q '^LAB_TIER=' "$ROOT/collaboration/.env.docker" || echo "LAB_TIER=test" >>"$ROOT/collaboration/.env.docker"
  else
    _ex="$ROOT/collaboration/.env.docker.${tier}.example"
    _out="$ROOT/collaboration/.env.docker.${tier}"
    if [ ! -f "$_out" ] && [ -f "$_ex" ]; then
      cp "$_ex" "$_out"
      sed -i "s|172.16.50.39|${SERVER_IP}|g" "$_out"
      sed -i "s|SelamnewCollaboration/environments/${tier}|SelamnewCollaboration/environments/${tier}|g" "$_out"
      log "Created $_out"
    fi
    _nex="$ROOT/notification/.env.docker.${tier}.example"
    _nout="$ROOT/notification/.env.docker.${tier}"
    if [ "$tier" = test ]; then
      _nex="$ROOT/notification/.env.docker.example"
      _nout="$ROOT/notification/.env.docker"
    fi
    if [ ! -f "$_nout" ] && [ -f "$_nex" ]; then
      cp "$_nex" "$_nout"
      sed -i "s|172.16.50.39|${SERVER_IP}|g" "$_nout"
      log "Created $_nout"
    fi
  fi

  if [ "$tier" != test ]; then
    for f in backend.env frontend.env; do
      _out="$ROOT/collaboration/env/${tier}/${f}"
      if [ ! -f "$_out" ] && [ -f "$ROOT/collaboration/env/backend.env" ]; then
        cp "$ROOT/collaboration/env/backend.env" "$ROOT/collaboration/env/${tier}/backend.env" 2>/dev/null || true
      fi
      if [ ! -f "$_out" ] && [ -f "$ROOT/collaboration/env/frontend.env" ] && [ "$f" = frontend.env ]; then
        cp "$ROOT/collaboration/env/frontend.env" "$_out"
      fi
    done
    _nes_out="$ROOT/notification/env/${tier}/notification.env"
    if [ ! -f "$_nes_out" ] && [ -f "$ROOT/notification/env/notification.env" ]; then
      cp "$ROOT/notification/env/notification.env" "$_nes_out"
    fi
  fi
done

LAB_TIER=all SERVER_IP="$SERVER_IP" bash "$ROOT/scripts/configure-lab-communication.sh"

log "Multi-env layout ready. Next:"
echo "  1. bash scripts/vault-import-all-env.sh  (or apply-vault-env per tier in Vault UI)"
echo "  2. sudo cp nginx/selamnew-collab.conf /etc/nginx/sites-available/selamnew-collab && sudo nginx -t && sudo systemctl reload nginx"
echo "  3. bash jenkins/bin/sync-jobs.sh"
echo "  4. Jenkins: build-and-start per tier, or push develop|staging|production on GitHub"
