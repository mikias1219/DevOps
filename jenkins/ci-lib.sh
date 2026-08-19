# Shared helpers for Jenkins pipelines (sourced from /var/devops/jenkins/ci-lib.sh).
# Docker volume mounts must use the *host* path. Inside Jenkins the devops folder
# lives at /var/devops, but `docker run -v /var/devops/...` resolves on the host.

resolve_host_devops() {
  local name source
  for name in jenkins-jenkins-1 "$(hostname)"; do
    source="$(
      docker inspect "$name" \
        --format '{{range .Mounts}}{{if eq .Destination "/var/devops"}}{{.Source}}{{end}}{{end}}' \
        2>/dev/null || true
    )"
    if [ -n "${source:-}" ]; then
      printf '%s' "$source"
      return 0
    fi
  done
  echo "Could not resolve host path for /var/devops mount" >&2
  return 1
}
