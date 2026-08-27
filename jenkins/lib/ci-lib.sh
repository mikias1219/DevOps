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
