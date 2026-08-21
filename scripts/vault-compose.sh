# Start / stop Vault
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec docker compose -f "$ROOT/vault/docker-compose.yml" "$@"
