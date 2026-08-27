#!/usr/bin/env bash
# Remove local node_modules — apps run from Docker images.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COL="$(grep '^COLLABORATION_SOURCE=' "$ROOT/collaboration/.env.docker" | cut -d= -f2-)"

remove_nm() {
  local dir="$1"
  if [[ -d "$dir/node_modules" ]]; then
    echo "Removing $dir/node_modules"
    rm -rf "$dir/node_modules"
  fi
}

remove_nm "$COL/backend"
remove_nm "$COL/frontend"

echo "Local node_modules removed. Deploy via Jenkins ACTION=build-and-start."
