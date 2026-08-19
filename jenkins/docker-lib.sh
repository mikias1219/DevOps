# Shared Jenkins + Docker helpers (sourced from /var/devops/jenkins/docker-lib.sh)
# POSIX sh — Jenkins agents use dash (/bin/sh), not bash.

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -i /var/jenkins_home/.ssh-host/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/var/devops/jenkins/github-known_hosts -o StrictHostKeyChecking=yes}"

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

# Always npm install into a bind-mounted app dir (used before Jenkins build/update).
install_npm_packages() {
  dir="$1"
  if [ ! -f "$dir/package.json" ]; then
    echo "No package.json in $dir" >&2
    return 1
  fi
  echo "==> npm install in $dir"
  docker run --rm \
    -v "$dir:/app" \
    -w /app \
    node:20-bookworm-slim \
    sh -c 'apt-get update && apt-get install -y --no-install-recommends python3 make g++ >/dev/null && npm install --no-audit --no-fund --legacy-peer-deps'
}

# Install only when node_modules is missing (start/restart).
ensure_npm_packages() {
  dir="$1"
  if [ ! -f "$dir/package.json" ]; then
    echo "No package.json in $dir" >&2
    return 1
  fi
  if [ -d "$dir/node_modules" ] && [ -f "$dir/node_modules/.package-lock.json" ]; then
    echo "==> packages already installed in $dir — skip npm install"
    return 0
  fi
  install_npm_packages "$dir"
}

git_pull_repo() {
  dir="$1"
  branch="$2"
  if [ ! -d "$dir/.git" ]; then
    echo "Not a git repo: $dir" >&2
    return 1
  fi
  ssh_url="$(to_github_ssh_url "$(git -C "$dir" remote get-url origin)")"
  echo "==> git fetch $dir ($branch) via $ssh_url"
  git -C "$dir" fetch "$ssh_url" "+refs/heads/${branch}:refs/remotes/origin/${branch}"
  current="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ "$current" != "$branch" ]; then
    git -C "$dir" checkout "$branch"
  fi
  git -C "$dir" merge --ff-only "origin/${branch}"
}

watch_state_dir() {
  mkdir -p /var/devops/.watch-state
  printf '%s' /var/devops/.watch-state
}

github_head_sha() {
  dir="$1"
  branch="$2"
  if [ ! -d "$dir/.git" ]; then
    return 1
  fi
  origin_url="$(git -C "$dir" remote get-url origin)"
  ssh_url="$(to_github_ssh_url "$origin_url")"
  git ls-remote "$ssh_url" "refs/heads/${branch}" | awk '{print $1}'
}

# Return 0 if GitHub SHA differs from the last recorded SHA.
# Does not update the SHA file (the Jenkins job records it when it rebuilds).
# First sight of a repo only records the SHA and returns 1 (no rebuild).
github_change_pending() {
  name="$1"
  dir="$2"
  branch="$3"
  state="$(watch_state_dir)"
  sha_file="${state}/${name}.sha"

  remote="$(github_head_sha "$dir" "$branch" || true)"
  if [ -z "$remote" ]; then
    echo "SKIP $name: could not read GitHub ${branch}" >&2
    return 1
  fi

  last=""
  if [ -f "$sha_file" ]; then
    last="$(tr -d '[:space:]' <"$sha_file")"
  fi

  if [ -z "$last" ]; then
    printf '%s\n' "$remote" >"$sha_file"
    echo "$name: recorded ${branch} SHA (no rebuild)"
    return 1
  fi

  if [ "$remote" = "$last" ]; then
    return 1
  fi

  echo "$name: GitHub change ${last} -> ${remote}"
  return 0
}

# If GitHub <branch> SHA changed vs last poll, return 0.
# First poll only records SHA and returns 1 (no rebuild).
repo_changed_on_github() {
  name="$1"
  dir="$2"
  branch="$3"
  state="$(watch_state_dir)"
  sha_file="${state}/${name}.sha"

  if [ ! -d "$dir/.git" ]; then
    echo "SKIP $name: not a git repo ($dir)" >&2
    return 1
  fi

  origin_url="$(git -C "$dir" remote get-url origin)"
  ssh_url="$(to_github_ssh_url "$origin_url")"
  remote="$(git ls-remote "$ssh_url" "refs/heads/${branch}" | awk '{print $1}')" || remote=""
  if [ -z "$remote" ]; then
    echo "SKIP $name: could not read $ssh_url refs/heads/${branch}" >&2
    return 1
  fi

  last=""
  if [ -f "$sha_file" ]; then
    last="$(tr -d '[:space:]' <"$sha_file")"
  fi

  echo "$name branch=${branch} remote=${remote} last=${last:-none}"

  if [ -z "$last" ]; then
    printf '%s\n' "$remote" >"$sha_file"
    echo "$name: first poll, recorded SHA (no rebuild)"
    return 1
  fi

  if [ "$remote" = "$last" ]; then
    echo "$name: no GitHub change"
    return 1
  fi

  printf '%s\n' "$remote" >"$sha_file"
  echo "$name: CHANGE detected ${last} -> ${remote}"
  return 0
}

trigger_jenkins_job() {
  job="$1"
  jenkins_url="${JENKINS_URL:-http://127.0.0.1:8080}"
  cookie="$(mktemp)"
  echo "==> Triggering ${job} ACTION=update-from-github"

  crumb_json="$(curl -sf -c "$cookie" "${jenkins_url}/crumbIssuer/api/json" || true)"
  field="$(printf '%s' "$crumb_json" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')"
  value="$(printf '%s' "$crumb_json" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')"

  out="$(mktemp)"
  if [ -n "$field" ] && [ -n "$value" ]; then
    code="$(
      curl -sS -o "$out" -w '%{http_code}' \
        -b "$cookie" -c "$cookie" \
        -H "${field}: ${value}" \
        -X POST \
        --data-urlencode "ACTION=update-from-github" \
        --data-urlencode "SKIP_TESTS=true" \
        "${jenkins_url}/job/${job}/buildWithParameters" || true
    )"
  else
    code="$(
      curl -sS -o "$out" -w '%{http_code}' \
        -b "$cookie" -c "$cookie" \
        -X POST \
        --data-urlencode "ACTION=update-from-github" \
        --data-urlencode "SKIP_TESTS=true" \
        "${jenkins_url}/job/${job}/buildWithParameters" || true
    )"
  fi
  rm -f "$cookie"

  case "$code" in
    200|201|302)
      echo "triggered ${job} (HTTP ${code})"
      ;;
    *)
      echo "WARN: could not trigger ${job} (HTTP ${code:-none})" >&2
      head -c 400 "$out" >&2 || true
      echo >&2
      ;;
  esac
  rm -f "$out"
}

poll_repo_and_trigger() {
  name="$1"
  dir="$2"
  branch="$3"
  job="$4"
  if repo_changed_on_github "$name" "$dir" "$branch"; then
    trigger_jenkins_job "$job"
  fi
}

trigger_watch_github_job() {
  job="${1:-watch-github}"
  jenkins_url="${JENKINS_URL:-http://127.0.0.1:8080}"
  cookie="$(mktemp)"
  echo "==> Starting Jenkins job ${job} (GitHub change detected)"

  crumb_json="$(curl -sf -c "$cookie" "${jenkins_url}/crumbIssuer/api/json" || true)"
  field="$(printf '%s' "$crumb_json" | sed -n 's/.*"crumbRequestField":"\([^"]*\)".*/\1/p')"
  value="$(printf '%s' "$crumb_json" | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')"

  out="$(mktemp)"
  if [ -n "$field" ] && [ -n "$value" ]; then
    code="$(
      curl -sS -o "$out" -w '%{http_code}' \
        -b "$cookie" -c "$cookie" \
        -H "${field}: ${value}" \
        -X POST \
        "${jenkins_url}/job/${job}/build" || true
    )"
  else
    code="$(
      curl -sS -o "$out" -w '%{http_code}' \
        -b "$cookie" -c "$cookie" \
        -X POST \
        "${jenkins_url}/job/${job}/build" || true
    )"
  fi
  rm -f "$cookie"

  case "$code" in
    200|201|302)
      echo "started ${job} (HTTP ${code})"
      ;;
    *)
      echo "WARN: could not start ${job} (HTTP ${code:-none})" >&2
      head -c 400 "$out" >&2 || true
      echo >&2
      ;;
  esac
  rm -f "$out"
}

env_file_get() {
  file="$1"
  key="$2"
  default="$3"
  val="$(grep "^${key}=" "$file" 2>/dev/null | cut -d= -f2- || true)"
  if [ -z "$val" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}

env_file_set() {
  file="$1"
  key="$2"
  value="$3"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

assert_safe_git_ref() {
  ref="$1"
  case "$ref" in
    '' | *[!A-Za-z0-9._/-]* | /* | */ | *..*)
      echo "Invalid branch name: ${ref}" >&2
      return 1
      ;;
  esac
}

list_github_branches() {
  dir="$1"
  if [ ! -d "$dir/.git" ]; then
    echo "Not a git repo: $dir" >&2
    return 1
  fi
  ssh_url="$(to_github_ssh_url "$(git -C "$dir" remote get-url origin)")"
  git ls-remote --heads "$ssh_url" | awk '{print $2}' | sed 's#^refs/heads/##' | sort
}

target_source_dir() {
  target="$1"
  col_env=/var/devops/collaboration/.env.docker
  hk_env=/var/devops/housekeeper/.env.docker
  col_src="$(env_file_get "$col_env" COLLABORATION_SOURCE "")"
  hk_src="$(env_file_get "$hk_env" HOUSEKEEPER_SOURCE "")"
  case "$target" in
    collaboration-backend | collaboration-both)
      printf '%s/backend' "$col_src"
      ;;
    collaboration-frontend)
      printf '%s/frontend' "$col_src"
      ;;
    housekeeper-backend | housekeeper-both)
      printf '%s/backend' "$hk_src"
      ;;
    housekeeper-frontend)
      printf '%s/frontend' "$hk_src"
      ;;
    *)
      echo "Unknown target: $target" >&2
      return 1
      ;;
  esac
}

current_watch_branch() {
  target="$1"
  col_env=/var/devops/collaboration/.env.docker
  hk_env=/var/devops/housekeeper/.env.docker
  case "$target" in
    collaboration-backend | collaboration-both)
      env_file_get "$col_env" COLLABORATION_BACKEND_BRANCH develop
      ;;
    collaboration-frontend)
      env_file_get "$col_env" COLLABORATION_FRONTEND_BRANCH develop
      ;;
    housekeeper-backend | housekeeper-both)
      env_file_get "$hk_env" HOUSEKEEPER_BACKEND_BRANCH main
      ;;
    housekeeper-frontend)
      env_file_get "$hk_env" HOUSEKEEPER_FRONTEND_BRANCH main
      ;;
  esac
}

# Switch watch + checkout. target is collaboration-backend|frontend|both or housekeeper-*.
switch_watch_target() {
  target="$1"
  branch="$2"
  rebuild="${3:-true}"
  assert_safe_git_ref "$branch"

  col_env=/var/devops/collaboration/.env.docker
  hk_env=/var/devops/housekeeper/.env.docker
  col_src="$(env_file_get "$col_env" COLLABORATION_SOURCE "")"
  hk_src="$(env_file_get "$hk_env" HOUSEKEEPER_SOURCE "")"
  state="$(watch_state_dir)"

  echo "==> Watch ${target} on branch ${branch} (rebuild=${rebuild})"

  case "$target" in
    collaboration-backend)
      env_file_set "$col_env" COLLABORATION_BACKEND_BRANCH "$branch"
      rm -f "${state}/collaboration-backend.sha"
      git_pull_repo "$col_src/backend" "$branch"
      if [ "$rebuild" = "true" ]; then
        trigger_jenkins_job collaboration-backend
      fi
      ;;
    collaboration-frontend)
      env_file_set "$col_env" COLLABORATION_FRONTEND_BRANCH "$branch"
      rm -f "${state}/collaboration-frontend.sha"
      git_pull_repo "$col_src/frontend" "$branch"
      if [ "$rebuild" = "true" ]; then
        trigger_jenkins_job collaboration-frontend
      fi
      ;;
    collaboration-both)
      env_file_set "$col_env" COLLABORATION_BACKEND_BRANCH "$branch"
      env_file_set "$col_env" COLLABORATION_FRONTEND_BRANCH "$branch"
      rm -f "${state}/collaboration-backend.sha" "${state}/collaboration-frontend.sha"
      git_pull_repo "$col_src/backend" "$branch"
      git_pull_repo "$col_src/frontend" "$branch"
      if [ "$rebuild" = "true" ]; then
        trigger_jenkins_job collaboration-backend
        trigger_jenkins_job collaboration-frontend
      fi
      ;;
    housekeeper-backend)
      env_file_set "$hk_env" HOUSEKEEPER_BACKEND_BRANCH "$branch"
      rm -f "${state}/housekeeper-backend.sha"
      git_pull_repo "$hk_src/backend" "$branch"
      if [ "$rebuild" = "true" ]; then
        trigger_jenkins_job housekeeper-backend
      fi
      ;;
    housekeeper-frontend)
      env_file_set "$hk_env" HOUSEKEEPER_FRONTEND_BRANCH "$branch"
      rm -f "${state}/housekeeper-frontend.sha"
      git_pull_repo "$hk_src/frontend" "$branch"
      if [ "$rebuild" = "true" ]; then
        trigger_jenkins_job housekeeper-frontend
      fi
      ;;
    housekeeper-both)
      env_file_set "$hk_env" HOUSEKEEPER_BACKEND_BRANCH "$branch"
      env_file_set "$hk_env" HOUSEKEEPER_FRONTEND_BRANCH "$branch"
      rm -f "${state}/housekeeper-backend.sha" "${state}/housekeeper-frontend.sha"
      git_pull_repo "$hk_src/backend" "$branch"
      git_pull_repo "$hk_src/frontend" "$branch"
      if [ "$rebuild" = "true" ]; then
        trigger_jenkins_job housekeeper-backend
        trigger_jenkins_job housekeeper-frontend
      fi
      ;;
    *)
      echo "Unknown target: $target" >&2
      return 1
      ;;
  esac

  echo "==> Now watching ${target} = ${branch}"
}

build_collaboration_backend() {
  source="$1"
  tag="${2:-collaboration-backend:local}"
  docker build -f /var/devops/collaboration/docker/backend.Dockerfile \
    -t "$tag" "$source/backend"
}

build_collaboration_frontend() {
  source="$1"
  tag="${2:-collaboration-frontend:local}"
  docker build -f /var/devops/collaboration/docker/frontend.Dockerfile \
    --build-arg NEXT_PUBLIC_COLLABORATION_URL=http://localhost:5000/api/v1 \
    --build-arg NEXT_PUBLIC_WS_URL=http://localhost:5000 \
    --build-arg NEXT_PUBLIC_API_URL=http://localhost:5000/api/v1 \
    -t "$tag" "$source/frontend"
}
