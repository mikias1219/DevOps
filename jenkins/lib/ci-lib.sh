# Host-path helpers. Docker -v paths are resolved on the daemon host, not
# inside the Jenkins container (where this repo is mounted at /var/devops).

resolve_host_devops() {
  _name=""
  _source=""
  for _name in jenkins-jenkins-1 jenkins_jenkins_1 "$(hostname 2>/dev/null || true)"; do
    [ -z "$_name" ] && continue
    _source="$(
      docker inspect "$_name" \
        --format '{{range .Mounts}}{{if eq .Destination "/var/devops"}}{{.Source}}{{end}}{{end}}' \
        2>/dev/null || true
    )"
    if [ -n "${_source:-}" ]; then
      printf '%s' "$_source"
      return 0
    fi
  done
  echo "Could not resolve host path for /var/devops" >&2
  return 1
}

# Jenkins official image has no python3. sync-jobs.sh needs it.
# Prefer host python3; otherwise run inside python:3.12-bookworm.
run_sync_jobs() {
  if command -v python3 >/dev/null 2>&1; then
    bash "${DEVOPS_ROOT:-/var/devops}/jenkins/bin/sync-jobs.sh"
    return
  fi
  _host="$(resolve_host_devops)"
  echo "==> python3 missing in this container; running sync-jobs via python:3.12-bookworm"
  docker run --rm --network host \
    -v "${_host}:/var/devops:rw" \
    -e JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}" \
    -e JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-}" \
    -e JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-}" \
    python:3.12-bookworm \
    bash -lc 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates >/dev/null && bash /var/devops/jenkins/bin/sync-jobs.sh'
}
