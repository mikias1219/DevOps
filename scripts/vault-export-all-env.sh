#!/usr/bin/env bash
# Export all Vault KV paths to collaboration/ and notification/ env files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-all}"

bash "$ROOT/scripts/ensure-vault-unsealed.sh"

export_path() {
  bash "$ROOT/scripts/vault-export-one.sh" "$1" "$2"
}

case "$TARGET" in
  all|both)
    # Unset TARGET so child script does not inherit TARGET=all from apply-vault-env
    TARGET=both bash "$ROOT/scripts/vault-export-collaboration-env.sh" both
    export_path "collaboration/notification" "$ROOT/notification/env/notification.env"
    ;;
  backend)
    TARGET=backend bash "$ROOT/scripts/vault-export-collaboration-env.sh" backend
    ;;
  frontend)
    TARGET=frontend bash "$ROOT/scripts/vault-export-collaboration-env.sh" frontend
    ;;
  notification)
    export_path "collaboration/notification" "$ROOT/notification/env/notification.env"
    ;;
  *)
    echo "TARGET must be all|both|backend|frontend|notification" >&2
    exit 1
    ;;
esac

echo "Export done."
