# Ensure jenkins/secrets/admin.env exists so compose env_file works.
# Run once after clone (does not overwrite existing admin.env).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/jenkins/secrets"
chmod 700 "$ROOT/jenkins/secrets"
if [[ ! -f "$ROOT/jenkins/secrets/admin.env" ]]; then
  cp "$ROOT/jenkins/secrets/admin.env.example" "$ROOT/jenkins/secrets/admin.env"
  chmod 600 "$ROOT/jenkins/secrets/admin.env"
  echo "Created jenkins/secrets/admin.env — set a strong JENKINS_ADMIN_PASS before production use."
else
  echo "admin.env already present"
fi
if [[ ! -f "$ROOT/jenkins/secrets/github-webhook-token.txt" ]]; then
  openssl rand -hex 16 >"$ROOT/jenkins/secrets/github-webhook-token.txt"
  chmod 600 "$ROOT/jenkins/secrets/github-webhook-token.txt"
  echo "Created github-webhook-token.txt"
fi
if [[ ! -f "$ROOT/jenkins/secrets/github-webhook-collab-token.txt" ]]; then
  echo -n "selamnew-collab-push" >"$ROOT/jenkins/secrets/github-webhook-collab-token.txt"
  chmod 600 "$ROOT/jenkins/secrets/github-webhook-collab-token.txt"
  echo "Created github-webhook-collab-token.txt (default selamnew-collab-push)"
fi
