#!/usr/bin/env bash
# Remove local node_modules — use Docker/Jenkins only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HK="$(grep '^HOUSEKEEPER_SOURCE=' "$ROOT/housekeeper/.env.docker" | cut -d= -f2-)"
COL="$(grep '^COLLABORATION_SOURCE=' "$ROOT/collaboration/.env.docker" | cut -d= -f2-)"

remove_nm() {
  local dir="$1"
  if [[ -d "$dir/node_modules" ]]; then
    echo "Removing $dir/node_modules"
    rm -rf "$dir/node_modules"
  fi
}

remove_nm "$HK/backend"
remove_nm "$HK/frontend"
remove_nm "$COL/backend"
remove_nm "$COL/frontend"
remove_nm "$COL/mobile" 2>/dev/null || true

echo
echo "Local node_modules removed. Run apps only via:"
echo "  Jenkins → Build with Parameters → ACTION=start | update-from-github"
echo "  or: ./scripts/start-all.sh"
