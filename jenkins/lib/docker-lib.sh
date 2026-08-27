# Shared helpers for Collaboration Jenkins pipelines.
# Sourced as /var/devops/jenkins/lib/docker-lib.sh
# POSIX sh — Jenkins agents use dash (/bin/sh).
#
# Jenkins talks to the host Docker daemon via /var/run/docker.sock.
# Compose files are readable at /var/devops inside the Jenkins container.
# Bind-mount sources in compose must be HOST paths (COLLABORATION_SOURCE).

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -i /var/jenkins_home/.ssh-host/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/var/devops/jenkins/github-known_hosts -o StrictHostKeyChecking=yes}"

DEVOPS_ROOT="${DEVOPS_ROOT:-/var/devops}"
COMPOSE_FILE="${COMPOSE_FILE:-${DEVOPS_ROOT}/collaboration/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${DEVOPS_ROOT}/collaboration/.env.docker}"
REGISTRY_COMPOSE="${DEVOPS_ROOT}/registry/docker-compose.yml"
DEFAULT_REGISTRY="127.0.0.1:5001"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

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

to_github_ssh_url() {
  _url="${1%.git}"
  case "$_url" in
    git@github.com:*)
      printf '%s.git\n' "$_url"
      ;;
    https://github.com/*)
      printf 'git@github.com:%s.git\n' "${_url#https://github.com/}"
      ;;
    http://github.com/*)
      printf 'git@github.com:%s.git\n' "${_url#http://github.com/}"
      ;;
    ssh://git@github.com/*)
      printf 'git@github.com:%s.git\n' "${_url#ssh://git@github.com/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# .env.docker
# ---------------------------------------------------------------------------

env_file_get() {
  _file="$1"
  _key="$2"
  _default="${3:-}"
  _val="$(grep "^${_key}=" "$_file" 2>/dev/null | cut -d= -f2- || true)"
  if [ -z "$_val" ]; then
    printf '%s' "$_default"
  else
    printf '%s' "$_val"
  fi
}

env_file_set() {
  _file="$1"
  _key="$2"
  _value="$3"
  if [ ! -f "$_file" ]; then
    printf '%s=%s\n' "$_key" "$_value" >>"$_file"
    return 0
  fi
  if grep -q "^${_key}=" "$_file"; then
    sed -i "s|^${_key}=.*|${_key}=${_value}|" "$_file"
  else
    printf '%s=%s\n' "$_key" "$_value" >>"$_file"
  fi
}

collaboration_source() {
  env_file_get "$ENV_FILE" COLLABORATION_SOURCE ""
}

backend_branch() {
  env_file_get "$ENV_FILE" COLLABORATION_BACKEND_BRANCH develop
}

frontend_branch() {
  env_file_get "$ENV_FILE" COLLABORATION_FRONTEND_BRANCH develop
}

registry_host() {
  env_file_get "$ENV_FILE" REGISTRY "$DEFAULT_REGISTRY"
}

print_environment() {
  echo "DEVOPS_ROOT=${DEVOPS_ROOT}"
  echo "COMPOSE_FILE=${COMPOSE_FILE}"
  echo "ENV_FILE=${ENV_FILE}"
  echo "COLLABORATION_SOURCE=$(collaboration_source)"
  echo "BACKEND_BRANCH=$(backend_branch)"
  echo "FRONTEND_BRANCH=$(frontend_branch)"
  echo "REGISTRY=$(registry_host)"
  echo "BACKEND_IMAGE_TAG=$(env_file_get "$ENV_FILE" BACKEND_IMAGE_TAG latest)"
  echo "FRONTEND_IMAGE_TAG=$(env_file_get "$ENV_FILE" FRONTEND_IMAGE_TAG latest)"
  echo "ACTION=${ACTION:-}"
}

# ---------------------------------------------------------------------------
# Git
# ---------------------------------------------------------------------------

assert_safe_git_ref() {
  _ref="$1"
  case "$_ref" in
    '' | *[!A-Za-z0-9._/-]* | /* | */ | *..*)
      echo "Invalid git ref: ${_ref}" >&2
      return 1
      ;;
  esac
}

git_pull_repo() {
  _dir="$1"
  _branch="$2"
  assert_safe_git_ref "$_branch"
  if [ ! -d "$_dir/.git" ]; then
    echo "Not a git repo: $_dir" >&2
    return 1
  fi
  _ssh_url="$(to_github_ssh_url "$(git -C "$_dir" remote get-url origin)")"
  echo "==> git fetch $_dir ($_branch) via $_ssh_url"
  git -C "$_dir" fetch "$_ssh_url" "+refs/heads/${_branch}:refs/remotes/origin/${_branch}"
  _current="$(git -C "$_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ "$_current" != "$_branch" ]; then
    git -C "$_dir" checkout "$_branch"
  fi
  git -C "$_dir" merge --ff-only "origin/${_branch}"
  echo "==> HEAD $(git -C "$_dir" log -1 --oneline)"
}

list_github_branches() {
  _dir="$1"
  if [ ! -d "$_dir/.git" ]; then
    echo "Not a git repo: $_dir" >&2
    return 1
  fi
  _ssh_url="$(to_github_ssh_url "$(git -C "$_dir" remote get-url origin)")"
  git ls-remote --heads "$_ssh_url" | awk '{print $2}' | sed 's#^refs/heads/##' | sort
}

# ---------------------------------------------------------------------------
# Registry + infra
# ---------------------------------------------------------------------------

ensure_local_registry() {
  if [ ! -f "$REGISTRY_COMPOSE" ]; then
    echo "Missing $REGISTRY_COMPOSE" >&2
    return 1
  fi
  echo "==> Ensuring local registry 127.0.0.1:5001"
  docker compose -f "$REGISTRY_COMPOSE" up -d
  _i=1
  while [ "$_i" -le 20 ]; do
    if curl -sf "http://127.0.0.1:5001/v2/" >/dev/null 2>&1; then
      echo "registry ready"
      return 0
    fi
    sleep 1
    _i=$((_i + 1))
  done
  echo "ERROR: registry did not start on 127.0.0.1:5001" >&2
  return 1
}

ensure_collaboration_infra() {
  if [ -f "${1:-}" ]; then
    COMPOSE_FILE="$1"
    ENV_FILE="${2:-$ENV_FILE}"
  fi
  echo "==> Ensuring collaboration db + redis + elasticsearch"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d db redis elasticsearch
}

# ---------------------------------------------------------------------------
# Quality — copy tree (read-only mount) so eslint --fix cannot dirty app git
# ---------------------------------------------------------------------------

_quality_copy_run() {
  _dir="$1"
  _script="$2"
  if [ ! -f "$_dir/package.json" ]; then
    echo "No package.json in $_dir" >&2
    return 1
  fi
  docker run --rm \
    -v "$_dir:/src:ro" \
    -w /tmp/src \
    node:20-bookworm-slim \
    sh -c "
      set -e
      apt-get update -qq >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 make g++ git >/dev/null
      cp -a /src/. /tmp/src
      cd /tmp/src
      npm install --no-audit --no-fund --legacy-peer-deps
      $_script
    "
}

quality_collaboration_backend() {
  _src="$(collaboration_source)/backend"
  echo "==> Quality: backend eslint (no --fix) + unit tests"
  _quality_copy_run "$_src" \
    'npx eslint "{src,apps,libs,test}/**/*.ts" && npm test -- --passWithNoTests'
}

quality_collaboration_frontend() {
  _src="$(collaboration_source)/frontend"
  echo "==> Quality: frontend eslint (no --fix)"
  _quality_copy_run "$_src" \
    'npx eslint .'
}

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

_git_sha() {
  git -C "$1" rev-parse --short=12 HEAD
}

_git_branch_name() {
  git -C "$1" rev-parse --abbrev-ref HEAD
}

_frontend_public_arg() {
  _key="$1"
  _default="$2"
  env_file_get "${DEVOPS_ROOT}/collaboration/env/frontend.env" "$_key" "$_default"
}

build_and_push_collaboration_backend() {
  _src="$(collaboration_source)/backend"
  _reg="$(registry_host)"
  _sha="$(_git_sha "$_src")"
  _branch="$(_git_branch_name "$_src")"
  _image="${_reg}/collaboration-backend"
  ensure_local_registry
  echo "==> docker build ${_image}:${_sha}"
  DOCKER_BUILDKIT=1 docker build \
    -f "${DEVOPS_ROOT}/collaboration/docker/backend.Dockerfile" \
    -t "${_image}:${_sha}" \
    -t "${_image}:${_branch}" \
    "$_src"
  echo "==> docker push ${_image}:${_sha} and :${_branch}"
  docker push "${_image}:${_sha}"
  docker push "${_image}:${_branch}"
  env_file_set "$ENV_FILE" BACKEND_IMAGE_TAG "$_sha"
  echo "BACKEND_IMAGE_TAG=${_sha}"
}

build_and_push_collaboration_frontend() {
  _src="$(collaboration_source)/frontend"
  _reg="$(registry_host)"
  _sha="$(_git_sha "$_src")"
  _branch="$(_git_branch_name "$_src")"
  _image="${_reg}/collaboration-frontend"
  _api_v1="$(_frontend_public_arg NEXT_PUBLIC_COLLABORATION_URL http://172.16.50.39:5000/api/v1)"
  _ws="$(_frontend_public_arg NEXT_PUBLIC_WS_URL http://172.16.50.39:5000)"
  _api="$(_frontend_public_arg NEXT_PUBLIC_API_URL http://172.16.50.39:5000/api/v1)"
  _api_base="$(_frontend_public_arg NEXT_PUBLIC_API_BASE_URL http://172.16.50.39:5000/api/v1)"
  _sock="$(_frontend_public_arg NEXT_PUBLIC_COLLABORATION_SOCKET_URL http://172.16.50.39:5000)"
  _app="$(_frontend_public_arg NEXT_PUBLIC_APP_URL http://172.16.50.39:3000)"
  ensure_local_registry
  echo "==> docker build ${_image}:${_sha}"
  DOCKER_BUILDKIT=1 docker build \
    -f "${DEVOPS_ROOT}/collaboration/docker/frontend.Dockerfile" \
    --build-arg "NEXT_PUBLIC_COLLABORATION_URL=${_api_v1}" \
    --build-arg "NEXT_PUBLIC_WS_URL=${_ws}" \
    --build-arg "NEXT_PUBLIC_API_URL=${_api}" \
    --build-arg "NEXT_PUBLIC_API_BASE_URL=${_api_base}" \
    --build-arg "NEXT_PUBLIC_COLLABORATION_SOCKET_URL=${_sock}" \
    --build-arg "NEXT_PUBLIC_APP_URL=${_app}" \
    -t "${_image}:${_sha}" \
    -t "${_image}:${_branch}" \
    "$_src"
  echo "==> docker push ${_image}:${_sha} and :${_branch}"
  docker push "${_image}:${_sha}"
  docker push "${_image}:${_branch}"
  env_file_set "$ENV_FILE" FRONTEND_IMAGE_TAG "$_sha"
  echo "FRONTEND_IMAGE_TAG=${_sha}"
}

# ---------------------------------------------------------------------------
# Deploy + smoke
# ---------------------------------------------------------------------------

deploy_collaboration_service() {
  _service="$1"
  echo "==> compose up --no-deps --force-recreate ${_service}"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
    up -d --no-deps --force-recreate "$_service"
}

stop_collaboration_service() {
  _service="$1"
  echo "==> compose stop ${_service}"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop "$_service"
}

wait_collaboration_backend_smoke() {
  if [ -f "${1:-}" ]; then
    COMPOSE_FILE="$1"
    ENV_FILE="$2"
    _service="${3:-backend}"
    _max="${4:-90}"
  else
    _service="${1:-backend}"
    _max="${2:-90}"
  fi
  _probe="require('http').get('http://127.0.0.1:5000/api/v1/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
  echo "==> Waiting for ${_service} GET /api/v1/health"
  _i=1
  while [ "$_i" -le "$_max" ]; do
    _state="$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps "$_service" --format '{{.State}}' 2>/dev/null || true)"
    if [ "$_state" != "running" ]; then
      echo "  attempt ${_i}/${_max}: state=${_state:-unknown}"
    elif docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T "$_service" node -e "$_probe"; then
      echo "collaboration backend healthy"
      return 0
    else
      echo "  attempt ${_i}/${_max}: health probe failed"
    fi
    sleep 3
    _i=$((_i + 1))
  done
  echo "ERROR: ${_service} not healthy after ${_max} attempts" >&2
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps db redis elasticsearch "$_service" 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --tail 120 "$_service" 2>&1 || true
  return 1
}

wait_collaboration_frontend_smoke() {
  if [ -f "${1:-}" ]; then
    COMPOSE_FILE="$1"
    ENV_FILE="$2"
    _service="${3:-frontend}"
    _max="${4:-60}"
  else
    _service="${1:-frontend}"
    _max="${2:-60}"
  fi
  _probe="require('http').get('http://127.0.0.1:3001/',r=>process.exit(r.statusCode<500?0:1)).on('error',()=>process.exit(1))"
  echo "==> Waiting for ${_service} GET /"
  _i=1
  while [ "$_i" -le "$_max" ]; do
    _state="$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps "$_service" --format '{{.State}}' 2>/dev/null || true)"
    if [ "$_state" != "running" ]; then
      echo "  attempt ${_i}/${_max}: state=${_state:-unknown}"
    elif docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T "$_service" node -e "$_probe"; then
      echo "collaboration frontend healthy"
      return 0
    else
      echo "  attempt ${_i}/${_max}: health probe failed"
    fi
    sleep 3
    _i=$((_i + 1))
  done
  echo "ERROR: ${_service} not healthy after ${_max} attempts" >&2
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps "$_service" 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --tail 120 "$_service" 2>&1 || true
  return 1
}

# ---------------------------------------------------------------------------
# Watch-branch (collaboration only)
# ---------------------------------------------------------------------------

target_source_dir() {
  _target="$1"
  _src="$(collaboration_source)"
  case "$_target" in
    collaboration-backend | collaboration-both)
      printf '%s/backend' "$_src"
      ;;
    collaboration-frontend)
      printf '%s/frontend' "$_src"
      ;;
    *)
      echo "Unknown target: $_target (collaboration only)" >&2
      return 1
      ;;
  esac
}

current_watch_branch() {
  _target="$1"
  case "$_target" in
    collaboration-backend | collaboration-both)
      backend_branch
      ;;
    collaboration-frontend)
      frontend_branch
      ;;
    *)
      echo "Unknown target: $_target" >&2
      return 1
      ;;
  esac
}

switch_watch_target() {
  _target="$1"
  _branch="$2"
  _rebuild="${3:-true}"
  assert_safe_git_ref "$_branch"
  _src="$(collaboration_source)"
  echo "==> Watch ${_target} on ${_branch} (rebuild=${_rebuild})"
  case "$_target" in
    collaboration-backend)
      env_file_set "$ENV_FILE" COLLABORATION_BACKEND_BRANCH "$_branch"
      git_pull_repo "$_src/backend" "$_branch"
      ;;
    collaboration-frontend)
      env_file_set "$ENV_FILE" COLLABORATION_FRONTEND_BRANCH "$_branch"
      git_pull_repo "$_src/frontend" "$_branch"
      ;;
    collaboration-both)
      env_file_set "$ENV_FILE" COLLABORATION_BACKEND_BRANCH "$_branch"
      env_file_set "$ENV_FILE" COLLABORATION_FRONTEND_BRANCH "$_branch"
      git_pull_repo "$_src/backend" "$_branch"
      git_pull_repo "$_src/frontend" "$_branch"
      ;;
    *)
      echo "Unknown target: $_target (housekeeper removed)" >&2
      return 1
      ;;
  esac
}

# Bind-mount era helpers. Images now own node_modules.
ensure_npm_packages() { echo "==> skip host npm (deps live in the image)"; }
install_npm_packages() { ensure_npm_packages "$@"; }
