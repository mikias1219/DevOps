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
  _src="$(env_file_get "$ENV_FILE" COLLABORATION_SOURCE "")"
  if [ -n "$_src" ] && [ -d "$_src" ]; then
    printf '%s' "$_src"
    return 0
  fi
  for _try in \
    /home/ienetworks/workspace/company/SelamnewCollaboration \
    /home/mikias/workspace/company/SelamnewCollaboration; do
    if [ -d "$_try" ]; then
      printf '%s' "$_try"
      return 0
    fi
  done
  printf '%s' "$_src"
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
    _cid="$(docker compose -f "$REGISTRY_COMPOSE" ps -q registry 2>/dev/null || true)"
    _running="$(docker inspect -f '{{.State.Running}}' "$_cid" 2>/dev/null || echo false)"
    # Jenkins runs in a container: curl 127.0.0.1 would hit Jenkins, not the host.
    # Probe via the host network namespace (same as dockerd / docker push).
    if [ "$_running" = "true" ] && docker run --rm --network host --entrypoint wget busybox:1.36 \
      -qO- http://127.0.0.1:5001/v2/ >/dev/null 2>&1; then
      echo "registry ready"
      return 0
    fi
    if [ "$_running" = "true" ] && [ "$_i" -ge 3 ]; then
      echo "registry container is running (HTTP probe skipped or slow — dockerd will use host 127.0.0.1:5001)"
      return 0
    fi
    sleep 1
    _i=$((_i + 1))
  done
  echo "ERROR: registry did not start on 127.0.0.1:5001" >&2
  docker compose -f "$REGISTRY_COMPOSE" ps >&2 || true
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
  _node_image="${3:-node:20-bookworm-slim}"
  if [ ! -f "$_dir/package.json" ]; then
    echo "No package.json in $_dir" >&2
    return 0
  fi
  # Report-only quality: never fail the pipeline. Copy tree so eslint --fix
  # cannot dirty the app repo. npm install may fail on slow networks (bcrypt).
  docker run --rm \
    -v "$_dir:/src:ro" \
    -w /tmp/src \
    "$_node_image" \
    sh -c "
      set +e
      cp -a /src/. /tmp/src
      cd /tmp/src
      npm config set fetch-timeout 600000 fetch-retries 5 >/dev/null 2>&1 || true
      npm install --no-audit --no-fund --legacy-peer-deps \
        || echo 'WARN: npm install failed in quality stage (not failing pipeline)'
      $_script
      exit 0
    "
}

quality_collaboration_backend() {
  _src="$(collaboration_source)/backend"
  echo "==> Quality: backend eslint + unit tests (report only)"
  echo "    We do not --fix or rewrite app tests — this lab does not own the backend repo."
  echo "    Failures are logged; they do not fail the pipeline. Image build + smoke are the gate."
  _quality_copy_run "$_src" \
    'npx eslint "{src,apps,libs,test}/**/*.ts" || echo "WARN: eslint reported issues (not failing)"; npm test -- --passWithNoTests || echo "WARN: unit tests failed (app-owned specs, not failing this lab pipeline)"'
}

quality_collaboration_frontend() {
  _src="$(collaboration_source)/frontend"
  echo "==> Quality: frontend eslint (report only, no --fix)"
  _quality_copy_run "$_src" \
    'npx eslint . || echo "WARN: eslint reported issues (not failing)"'
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

_registry_has_tag() {
  _image="$1"
  _tag="$2"
  docker pull "${_image}:${_tag}" >/dev/null 2>&1
}

lab_node_image() {
  printf '%s/lab-node:20' "$(registry_host)"
}

# One-time base with g++/python — app Dockerfiles never run apt-get.
ensure_lab_node_base() {
  _img="$(lab_node_image)"
  if docker image inspect "$_img" >/dev/null 2>&1; then
    echo "==> lab-node base ready (${_img})"
    return 0
  fi
  if docker pull "$_img" >/dev/null 2>&1; then
    echo "==> pulled lab-node base (${_img})"
    return 0
  fi
  echo "==> Building lab-node base ONCE (apt tools — slow first time only)"
  DOCKER_BUILDKIT=1 docker build \
    -f "${DEVOPS_ROOT}/collaboration/docker/lab-node.Dockerfile" \
    -t "$_img" \
    "${DEVOPS_ROOT}/collaboration/docker"
  docker push "$_img" 2>/dev/null || true
}

# BuildKit + pull :latest for layer reuse + inline cache for next builds.
# Extra args are passed to `docker build` (must include -f, -t's, context).
_docker_build_with_cache() {
  _cache_image="$1"
  shift
  export DOCKER_BUILDKIT=1
  echo "==> BuildKit cache: pulling ${_cache_image}:latest (if present)"
  docker pull "${_cache_image}:latest" >/dev/null 2>&1 || true
  docker build \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --cache-from "${_cache_image}:latest" \
    "$@"
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
  if _registry_has_tag "$_image" "$_sha"; then
    echo "==> skip build: ${_image}:${_sha} already in registry (FAST PATH)"
    env_file_set "$ENV_FILE" BACKEND_IMAGE_TAG "$_sha"
    echo "BACKEND_IMAGE_TAG=${_sha}"
    return 0
  fi
  ensure_lab_node_base
  echo "==> docker build ${_image}:${_sha} (BuildKit cache — uses lab-node base)"
  _docker_build_with_cache "$_image" \
    -f "${DEVOPS_ROOT}/collaboration/docker/backend.Dockerfile" \
    --build-arg "LAB_NODE=$(lab_node_image)" \
    -t "${_image}:${_sha}" \
    -t "${_image}:${_branch}" \
    -t "${_image}:latest" \
    "$_src"
  echo "==> docker push ${_image}:${_sha} and :${_branch}"
  docker push "${_image}:${_sha}"
  docker push "${_image}:${_branch}"
  docker push "${_image}:latest"
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
  _fb_key="$(_frontend_public_arg NEXT_PUBLIC_API_KEY "")"
  _fb_domain="$(_frontend_public_arg NEXT_PUBLIC_AUTH_DOMAIN "")"
  _fb_project="$(_frontend_public_arg NEXT_PUBLIC_PROJECT_ID "")"
  _fb_bucket="$(_frontend_public_arg NEXT_PUBLIC_STORAGE_BUCKET "")"
  _fb_sender="$(_frontend_public_arg NEXT_PUBLIC_MESSAGE_SENDER_ID "")"
  _fb_app="$(_frontend_public_arg NEXT_PUBLIC_APP_ID "")"
  _org_emp="$(_frontend_public_arg NEXT_PUBLIC_ORG_AND_EMP_URL "")"
  _enc_disabled="$(_frontend_public_arg NEXT_PUBLIC_ENCRYPTION_DISABLED true)"
  _enc_key="$(_frontend_public_arg NEXT_PUBLIC_ENCRYPTION_KEY "")"
  _enc_salt="$(_frontend_public_arg NEXT_PUBLIC_ENCRYPTION_SALT "")"
  _enc_iv="$(_frontend_public_arg NEXT_PUBLIC_ENCRYPTION_IV "")"
  if [ -z "$_fb_key" ]; then
    echo "FATAL: NEXT_PUBLIC_API_KEY is empty in collaboration/env/frontend.env" >&2
    echo "Next.js prerender calls Firebase at build time. Add the key (do not commit it)." >&2
    return 1
  fi
  if [ -z "$_org_emp" ]; then
    echo "FATAL: NEXT_PUBLIC_ORG_AND_EMP_URL is empty in collaboration/env/frontend.env" >&2
    echo "Login posts credentials to org-emp; bake this URL into the Next.js build." >&2
    return 1
  fi
  ensure_local_registry
  if [ "${FORCE_REBUILD:-}" != "1" ] && _registry_has_tag "$_image" "$_sha"; then
    echo "==> skip build: ${_image}:${_sha} already in registry (FAST PATH)"
    echo "    (set FORCE_REBUILD=1 to rebuild when only bake-time env/Dockerfile changed)"
    env_file_set "$ENV_FILE" FRONTEND_IMAGE_TAG "$_sha"
    echo "FRONTEND_IMAGE_TAG=${_sha}"
    return 0
  fi
  ensure_lab_node_base
  echo "==> docker build ${_image}:${_sha} (BuildKit cache — uses lab-node base)"
  echo "    ENCRYPTION_DISABLED=${_enc_disabled} ORG_AND_EMP_URL=${_org_emp}"
  _docker_build_with_cache "$_image" \
    -f "${DEVOPS_ROOT}/collaboration/docker/frontend.Dockerfile" \
    --build-arg "LAB_NODE=$(lab_node_image)" \
    --build-arg "NEXT_PUBLIC_COLLABORATION_URL=${_api_v1}" \
    --build-arg "NEXT_PUBLIC_WS_URL=${_ws}" \
    --build-arg "NEXT_PUBLIC_API_URL=${_api}" \
    --build-arg "NEXT_PUBLIC_API_BASE_URL=${_api_base}" \
    --build-arg "NEXT_PUBLIC_COLLABORATION_SOCKET_URL=${_sock}" \
    --build-arg "NEXT_PUBLIC_APP_URL=${_app}" \
    --build-arg "NEXT_PUBLIC_API_KEY=${_fb_key}" \
    --build-arg "NEXT_PUBLIC_AUTH_DOMAIN=${_fb_domain}" \
    --build-arg "NEXT_PUBLIC_PROJECT_ID=${_fb_project}" \
    --build-arg "NEXT_PUBLIC_STORAGE_BUCKET=${_fb_bucket}" \
    --build-arg "NEXT_PUBLIC_MESSAGE_SENDER_ID=${_fb_sender}" \
    --build-arg "NEXT_PUBLIC_APP_ID=${_fb_app}" \
    --build-arg "NEXT_PUBLIC_ORG_AND_EMP_URL=${_org_emp}" \
    --build-arg "NEXT_PUBLIC_ENCRYPTION_DISABLED=${_enc_disabled}" \
    --build-arg "NEXT_PUBLIC_ENCRYPTION_KEY=${_enc_key}" \
    --build-arg "NEXT_PUBLIC_ENCRYPTION_SALT=${_enc_salt}" \
    --build-arg "NEXT_PUBLIC_ENCRYPTION_IV=${_enc_iv}" \
    -t "${_image}:${_sha}" \
    -t "${_image}:${_branch}" \
    -t "${_image}:latest" \
    "$_src"
  echo "==> docker push ${_image}:${_sha} and :${_branch}"
  docker push "${_image}:${_sha}"
  docker push "${_image}:${_branch}"
  docker push "${_image}:latest"
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

# ---------------------------------------------------------------------------
# Notification-and-email-service (third app — lab mirrors production Jenkinsfile)
# ---------------------------------------------------------------------------

NOTIFICATION_COMPOSE="${DEVOPS_ROOT}/notification/docker-compose.yml"
NOTIFICATION_ENV_FILE="${DEVOPS_ROOT}/notification/.env.docker"

notification_source() {
  _base="$(collaboration_source)"
  if [ -n "$_base" ]; then
    printf '%s/Notification-and-email-service' "$_base"
    return 0
  fi
  env_file_get "$NOTIFICATION_ENV_FILE" COLLABORATION_SOURCE ""
}

notification_branch() {
  _branch="$(env_file_get "$ENV_FILE" COLLABORATION_NOTIFICATION_BRANCH "")"
  if [ -n "$_branch" ]; then
    printf '%s' "$_branch"
    return 0
  fi
  env_file_get "$NOTIFICATION_ENV_FILE" NOTIFICATION_BRANCH develop
}

print_notification_environment() {
  echo "NOTIFICATION_COMPOSE=${NOTIFICATION_COMPOSE}"
  echo "NOTIFICATION_ENV_FILE=${NOTIFICATION_ENV_FILE}"
  echo "NOTIFICATION_SOURCE=$(notification_source)"
  echo "NOTIFICATION_BRANCH=$(notification_branch)"
  echo "REGISTRY=$(registry_host)"
  echo "NOTIFICATION_IMAGE_TAG=$(env_file_get "$NOTIFICATION_ENV_FILE" NOTIFICATION_IMAGE_TAG latest)"
  echo "ACTION=${ACTION:-}"
}

ensure_notification_infra() {
  echo "==> Ensuring notification db"
  docker compose -f "$NOTIFICATION_COMPOSE" --env-file "$NOTIFICATION_ENV_FILE" up -d db
}

quality_collaboration_notification() {
  _src="$(notification_source)"
  echo "==> Quality: notification eslint (report only)"
  _quality_copy_run "$_src" \
    'npx eslint "src/**/*.{js,ts}" || echo "WARN: eslint reported issues (not failing)"' \
    node:18-bookworm-slim
}

build_and_push_collaboration_notification() {
  _src="$(notification_source)"
  _reg="$(registry_host)"
  _sha="$(_git_sha "$_src")"
  _branch="$(_git_branch_name "$_src")"
  _image="${_reg}/collaboration-notification"
  ensure_local_registry
  if _registry_has_tag "$_image" "$_sha"; then
    echo "==> skip build: ${_image}:${_sha} already in registry (FAST PATH)"
    env_file_set "$NOTIFICATION_ENV_FILE" NOTIFICATION_IMAGE_TAG "$_sha"
    echo "NOTIFICATION_IMAGE_TAG=${_sha}"
    return 0
  fi
  ensure_lab_node_base
  echo "==> docker build ${_image}:${_sha} (BuildKit cache — uses lab-node base)"
  _docker_build_with_cache "$_image" \
    -f "${DEVOPS_ROOT}/notification/docker/notification.Dockerfile" \
    --build-arg "LAB_NODE=$(lab_node_image)" \
    -t "${_image}:${_sha}" \
    -t "${_image}:${_branch}" \
    -t "${_image}:latest" \
    "$_src"
  echo "==> docker push ${_image}:${_sha} and :${_branch}"
  docker push "${_image}:${_sha}"
  docker push "${_image}:${_branch}"
  docker push "${_image}:latest"
  env_file_set "$NOTIFICATION_ENV_FILE" NOTIFICATION_IMAGE_TAG "$_sha"
  echo "NOTIFICATION_IMAGE_TAG=${_sha}"
}

deploy_notification_service() {
  _service="$1"
  echo "==> compose up --no-deps --force-recreate ${_service}"
  docker compose -f "$NOTIFICATION_COMPOSE" --env-file "$NOTIFICATION_ENV_FILE" \
    up -d --no-deps --force-recreate "$_service"
}

stop_notification_service() {
  _service="$1"
  echo "==> compose stop ${_service}"
  docker compose -f "$NOTIFICATION_COMPOSE" --env-file "$NOTIFICATION_ENV_FILE" stop "$_service"
}

wait_notification_smoke() {
  _service="${1:-notification}"
  _max="${2:-90}"
  _probe="require('http').get('http://127.0.0.1:8006/api/v1/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
  echo "==> Waiting for ${_service} GET /api/v1/health"
  _i=1
  while [ "$_i" -le "$_max" ]; do
    _state="$(docker compose -f "$NOTIFICATION_COMPOSE" --env-file "$NOTIFICATION_ENV_FILE" ps "$_service" --format '{{.State}}' 2>/dev/null || true)"
    if [ "$_state" != "running" ]; then
      echo "  attempt ${_i}/${_max}: state=${_state:-unknown}"
    elif docker compose -f "$NOTIFICATION_COMPOSE" --env-file "$NOTIFICATION_ENV_FILE" exec -T "$_service" node -e "$_probe"; then
      echo "notification service healthy"
      return 0
    else
      echo "  attempt ${_i}/${_max}: health probe failed"
    fi
    sleep 3
    _i=$((_i + 1))
  done
  echo "ERROR: ${_service} not healthy after ${_max} attempts" >&2
  docker compose -f "$NOTIFICATION_COMPOSE" --env-file "$NOTIFICATION_ENV_FILE" logs --tail 120 "$_service" 2>&1 || true
  return 1
}
