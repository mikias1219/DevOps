# Lab tier context: test (develop) | staging | production — mirrors prod branch → environment.
# Sourced from docker-lib.sh (POSIX sh).

LAB_SERVER_IP="${LAB_SERVER_IP:-172.16.50.39}"
LAB_SSH_USER="${LAB_SSH_USER:-ienetworks}"
LAB_DEVOPS_HOST="${LAB_DEVOPS_HOST:-/home/ienetworks/workspace/tools/docker-devops}"

lab_tier_from_branch() {
  _b="$1"
  case "$_b" in
    staging) printf 'staging' ;;
    production) printf 'production' ;;
    develop | develop-redesign | *) printf 'test' ;;
  esac
}

lab_branch_for_tier() {
  _t="$1"
  case "$_t" in
    staging) printf 'staging' ;;
    production) printf 'production' ;;
    *) printf 'develop' ;;
  esac
}

lab_tier_public_base() {
  _t="$1"
  case "$_t" in
    staging) printf 'http://%s/staging' "$LAB_SERVER_IP" ;;
    production) printf 'http://%s/production' "$LAB_SERVER_IP" ;;
    *) printf 'http://%s' "$LAB_SERVER_IP" ;;
  esac
}

lab_tier_compose_file() {
  _t="$1"
  case "$_t" in
    staging) printf '%s/collaboration/docker-compose.staging.yml' "$DEVOPS_ROOT" ;;
    production) printf '%s/collaboration/docker-compose.production.yml' "$DEVOPS_ROOT" ;;
    *) printf '%s/collaboration/docker-compose.yml' "$DEVOPS_ROOT" ;;
  esac
}

lab_tier_env_docker() {
  _t="$1"
  case "$_t" in
    staging) printf '%s/collaboration/.env.docker.staging' "$DEVOPS_ROOT" ;;
    production) printf '%s/collaboration/.env.docker.production' "$DEVOPS_ROOT" ;;
    *) printf '%s/collaboration/.env.docker' "$DEVOPS_ROOT" ;;
  esac
}

lab_tier_notification_compose() {
  _t="$1"
  case "$_t" in
    staging) printf '%s/notification/docker-compose.staging.yml' "$DEVOPS_ROOT" ;;
    production) printf '%s/notification/docker-compose.production.yml' "$DEVOPS_ROOT" ;;
    *) printf '%s/notification/docker-compose.yml' "$DEVOPS_ROOT" ;;
  esac
}

lab_tier_notification_env_docker() {
  _t="$1"
  case "$_t" in
    staging) printf '%s/notification/.env.docker.staging' "$DEVOPS_ROOT" ;;
    production) printf '%s/notification/.env.docker.production' "$DEVOPS_ROOT" ;;
    *) printf '%s/notification/.env.docker' "$DEVOPS_ROOT" ;;
  esac
}

lab_tier_secrets_file() {
  _app="$1"
  _t="$2"
  case "$_app" in
    backend) _f=".collab-back-env" ;;
    frontend) _f=".collab-fe-env" ;;
    notification) _f=".collab-nes-env" ;;
    *)
      echo "Unknown app for secrets: $_app" >&2
      return 1
      ;;
  esac
  printf '%s/collaboration/lab-secrets/%s/%s' "$DEVOPS_ROOT" "$_t" "$_f"
}

lab_tier_source_root() {
  _t="$1"
  _base="${LAB_COLLAB_ROOT:-}"
  if [ -z "$_base" ]; then
    _base="$(env_file_get "${DEVOPS_ROOT}/collaboration/.env.docker" COLLABORATION_SOURCE_PARENT "")"
  fi
  if [ -z "$_base" ]; then
    for _try in \
      /home/ienetworks/workspace/company/SelamnewCollaboration \
      /home/mikias/workspace/company/SelamnewCollaboration; do
      if [ -d "$_try" ]; then
        _base="$_try"
        break
      fi
    done
  fi
  printf '%s/environments/%s' "$_base" "$_t"
}

lab_apply_tier_context() {
  _tier="${1:-test}"
  _branch="${2:-}"
  case "$_tier" in
    test | staging | production) ;;
    *)
      echo "Invalid LAB_TIER: $_tier" >&2
      return 1
      ;;
  esac
  if [ -z "$_branch" ]; then
    _branch="$(lab_branch_for_tier "$_tier")"
  fi
  export LAB_TIER="$_tier"
  export LAB_GIT_BRANCH="$_branch"
  COMPOSE_FILE="$(lab_tier_compose_file "$_tier")"
  ENV_FILE="$(lab_tier_env_docker "$_tier")"
  NOTIFICATION_COMPOSE="$(lab_tier_notification_compose "$_tier")"
  NOTIFICATION_ENV_FILE="$(lab_tier_notification_env_docker "$_tier")"
  export COMPOSE_FILE ENV_FILE NOTIFICATION_COMPOSE NOTIFICATION_ENV_FILE
  export LAB_PUBLIC_BASE="$(lab_tier_public_base "$_tier")"
  export REMOTE_SERVER="${LAB_SSH_USER}@${LAB_SERVER_IP}"
  export SECRETS_PATH="$(lab_tier_secrets_file backend "$_tier")"
  _src="$(lab_tier_source_root "$_tier")"
  if [ -f "$ENV_FILE" ]; then
    env_file_set "$ENV_FILE" LAB_TIER "$_tier"
    env_file_set "$ENV_FILE" COLLABORATION_SOURCE "$_src"
    env_file_set "$ENV_FILE" COLLABORATION_BACKEND_BRANCH "$_branch"
    env_file_set "$ENV_FILE" COLLABORATION_FRONTEND_BRANCH "$_branch"
    env_file_set "$ENV_FILE" COLLABORATION_NOTIFICATION_BRANCH "$_branch"
  fi
  if [ -f "$NOTIFICATION_ENV_FILE" ]; then
    env_file_set "$NOTIFICATION_ENV_FILE" NOTIFICATION_BRANCH "$_branch"
    env_file_set "$NOTIFICATION_ENV_FILE" COLLABORATION_SOURCE "$_src"
  fi
  echo "==> LAB_TIER=${LAB_TIER} GIT_BRANCH=${LAB_GIT_BRANCH}"
  echo "    REMOTE_SERVER=${REMOTE_SERVER} (prod: SSH target; lab: same host, optional ssh for parity)"
  echo "    COMPOSE_FILE=${COMPOSE_FILE}"
  echo "    ENV_FILE=${ENV_FILE}"
  echo "    LAB_PUBLIC_BASE=${LAB_PUBLIC_BASE}"
  echo "    COLLABORATION_SOURCE=${_src}"
}

grep_lab_secret() {
  _file="$1"
  _key="$2"
  _default="${3:-}"
  if [ ! -f "$_file" ]; then
    printf '%s' "$_default"
    return 0
  fi
  _val="$(grep "^${_key}=" "$_file" 2>/dev/null | cut -d= -f2- || true)"
  if [ -z "$_val" ]; then
    printf '%s' "$_default"
  else
    printf '%s' "$_val"
  fi
}

fetch_application_variables_lab_ssh() {
  _app="$1"
  _secrets=""
  case "$_app" in
    backend) _secrets="$(lab_tier_secrets_file backend "${LAB_TIER:-test}")" ;;
    frontend) _secrets="$(lab_tier_secrets_file frontend "${LAB_TIER:-test}")" ;;
    notification) _secrets="$(lab_tier_secrets_file notification "${LAB_TIER:-test}")" ;;
    *)
      echo "Unknown app: $_app" >&2
      return 1
      ;;
  esac
  echo "==> Fetch Application Variables (prod: ssh grep on \${SECRETS_PATH})"
  echo "SECRETS_PATH=${_secrets}"
  _repo_url="$(grep_lab_secret "$_secrets" REPO_URL "")"
  _repo_dir="$(grep_lab_secret "$_secrets" REPO_DIR "")"
  _branch="$(grep_lab_secret "$_secrets" BRANCH_NAME "$(lab_branch_for_tier "${LAB_TIER:-test}")")"
  _docker_repo="$(grep_lab_secret "$_secrets" DOCKERHUB_REPO "")"
  _service="$(grep_lab_secret "$_secrets" SERVICE_NAME "")"
  if [ -z "$_repo_dir" ]; then
    case "$_app" in
      backend) _repo_dir="$(lab_tier_source_root "${LAB_TIER:-test}")/backend" ;;
      frontend) _repo_dir="$(lab_tier_source_root "${LAB_TIER:-test}")/frontend" ;;
      notification) _repo_dir="$(lab_tier_source_root "${LAB_TIER:-test}")/Notification-and-email-service" ;;
    esac
  fi
  if [ -z "$_docker_repo" ]; then
    _reg="$(registry_host)"
    case "$_app" in
      backend) _docker_repo="${_reg}/collaboration-backend" ;;
      frontend) _docker_repo="${_reg}/collaboration-frontend" ;;
      notification) _docker_repo="${_reg}/collaboration-notification" ;;
    esac
  fi
  if [ -z "$_service" ]; then
    _service="$_app"
  fi
  echo "REPO_URL=${_repo_url}"
  echo "REPO_DIR=${_repo_dir}"
  echo "BRANCH_NAME=${_branch}"
  echo "DOCKERHUB_REPO=${_docker_repo}"
  echo "SERVICE_NAME=${_service}"
  if [ "$_app" = frontend ]; then
    echo "VAULT_ADDR=$(grep_lab_secret "$_secrets" VAULT_ADDR 'http://127.0.0.1:8200')"
    echo "VAULT_SECRET_PATH=$(grep_lab_secret "$_secrets" VAULT_SECRET_PATH "secret/collaboration/${LAB_TIER:-test}/frontend")"
  fi
  test -d "$_repo_dir" || echo "WARN: REPO_DIR not present yet — Prepare Repository will clone"
}

prepare_repository_lab_ssh() {
  _dir="$1"
  echo "==> Prepare Repository (prod: ssh chown/chmod on REMOTE_SERVER)"
  if [ -d "$_dir" ]; then
    chmod -R u+rwX "$_dir" 2>/dev/null || true
  fi
}

ensure_tier_git_checkout() {
  _repo_dir="$1"
  _repo_url="$2"
  _branch="$3"
  assert_safe_git_ref "$_branch"
  if [ ! -d "$_repo_dir/.git" ]; then
    _parent="$(dirname "$_repo_dir")"
    mkdir -p "$_parent"
    echo "==> git clone ${_repo_url} -b ${_branch} ${_repo_dir}"
    git clone "$_repo_url" -b "$_branch" "$_repo_dir"
    return 0
  fi
  git_pull_repo "$_repo_dir" "$_branch"
}
