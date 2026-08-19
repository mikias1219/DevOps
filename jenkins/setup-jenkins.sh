#!/usr/bin/env bash
# Reset local Jenkins admin password (dev only) and register all pipeline jobs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/jenkins/docker-compose.yml"
JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-DevOps@2026}"

chmod +x "$ROOT/jenkins/"*.sh "$ROOT/scripts/"*.sh 2>/dev/null || true

echo "==> Ensuring Jenkins is running"
export DOCKER_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 124)"
docker compose -f "$COMPOSE_FILE" up -d

echo "==> Waiting for Jenkins HTTP..."
for i in $(seq 1 60); do
  if curl -sf "$JENKINS_URL/login" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

echo "==> Temporarily disabling security to bootstrap admin user"
docker compose -f "$COMPOSE_FILE" exec -T jenkins bash -lc "
  sed -i 's|<useSecurity>true</useSecurity>|<useSecurity>false</useSecurity>|' /var/jenkins_home/config.xml
"
docker compose -f "$COMPOSE_FILE" restart jenkins

for i in $(seq 1 60); do
  if curl -sf "$JENKINS_URL/login" >/dev/null 2>&1; then
    sleep 5
    break
  fi
  sleep 3
done

echo "==> Creating admin user via script console"
docker compose -f "$COMPOSE_FILE" exec -T jenkins bash -lc "
cat > /tmp/reset-admin.groovy <<'GROOVY'
import jenkins.model.*
import hudson.security.*

def jenkins = Jenkins.getInstance()
def username = '${JENKINS_ADMIN_USER}'
def password = '${JENKINS_ADMIN_PASS}'
def realm = jenkins.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
  realm = new HudsonPrivateSecurityRealm(false)
  jenkins.setSecurityRealm(realm)
}
def user = User.get(username, false)
if (user == null) {
  realm.createAccount(username, password)
  println 'Created ' + username
} else {
  def details = user.getProperty(HudsonPrivateSecurityRealm.Details.class)
  if (details != null) {
    details.setPasswordHash(HudsonPrivateSecurityRealm.CONSOLE.encode(password))
    user.save()
    println 'Reset password for ' + username
  }
}
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
jenkins.setAuthorizationStrategy(strategy)
jenkins.setSecurityRealm(realm)
jenkins.save()
GROOVY
curl -sf -X POST --data-urlencode \"script@/tmp/reset-admin.groovy\" \
  \"http://127.0.0.1:8080/scriptText\"
"

echo "==> Re-enabling security"
docker compose -f "$COMPOSE_FILE" exec -T jenkins bash -lc "
  sed -i 's|<useSecurity>false</useSecurity>|<useSecurity>true</useSecurity>|' /var/jenkins_home/config.xml
"
docker compose -f "$COMPOSE_FILE" restart jenkins

echo "==> Waiting for secured Jenkins..."
for i in $(seq 1 60); do
  if curl -sf -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}" "$JENKINS_URL/login" >/dev/null 2>&1; then
    echo "Authenticated (attempt $i)"
    break
  fi
  sleep 3
done

echo "==> Syncing Jenkins jobs"
JENKINS_ADMIN_USER="$JENKINS_ADMIN_USER" JENKINS_ADMIN_PASS="$JENKINS_ADMIN_PASS" \
  "$ROOT/jenkins/sync-jobs.sh"

echo
echo "============================================"
echo "Jenkins ready"
echo "  URL:      ${JENKINS_URL}"
echo "  User:     ${JENKINS_ADMIN_USER}"
echo "  Password: ${JENKINS_ADMIN_PASS}"
echo "============================================"
