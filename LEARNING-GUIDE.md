# DevOps Learning Lab — End-to-End Guide

Your learning server: **172.16.50.39** (`ienetworks`)

This lab mirrors production DevOps from `frontend/`, `backend/`, and `Notification-and-email-service/` **without editing those repos**. All pipelines, Dockerfiles, and compose files live here in `docker-devops/`.

---

## Quick start (one command)

**From your laptop** (after SSH key is set up):

```bash
cd docker-devops
bash scripts/install-from-laptop.sh --fresh
```

**On the server directly:**

```bash
cd /home/ienetworks/workspace/tools/docker-devops
bash scripts/reset-server.sh --wipe-volumes    # optional clean slate
bash scripts/bootstrap-learning-server.sh
```

---

## What gets installed

| Component | URL | Purpose |
|-----------|-----|---------|
| Jenkins | http://172.16.50.39:8080 | CI/CD — same stage flow as production Jenkinsfiles |
| Vault | http://172.16.50.39:8200/ui | Secrets store (like production HashiCorp Vault) |
| Secrets Room | http://172.16.50.39:8300 | UI to compare/export env from Vault |
| Local registry | 127.0.0.1:5001 | Image push/pull (lab replaces Docker Hub) |
| Portainer | https://172.16.50.39:9443 | Docker UI |
| Collab FE | http://172.16.50.39:3000 | Next.js |
| Collab BE | http://172.16.50.39:5000 | NestJS API |
| Notification | http://172.16.50.39:8006 | NES API |
| Adminer (collab) | http://172.16.50.39:8083 | DB admin |
| Adminer (NES) | http://172.16.50.39:8084 | DB admin |

---

## Production vs lab mapping

| Production (app repo Jenkinsfile) | Lab equivalent |
|-----------------------------------|----------------|
| Select Environment (branch → server) | `collaboration/.env.docker` + Jenkins ACTION |
| Fetch vars from `/home/ubuntu/secrets/` | `collaboration/env/*.env` + Vault |
| SSH remote build | Jenkins container → host Docker via socket |
| Docker Hub push | `127.0.0.1:5001` local registry |
| Docker Swarm deploy | `docker compose up --force-recreate` |
| Verify deployment | Smoke test `/api/v1/health` |
| Failure email | Jenkins console (no email in lab) |

---

## Jenkins jobs (practice here)

| Job | When to use |
|-----|-------------|
| `collaboration-backend` | Build/deploy Nest API — ACTION=`build-and-start` |
| `collaboration-frontend` | Build/deploy Next app |
| `collaboration-notification` | Build/deploy NES |
| `collaboration-stack` | Start/stop all collab services; `build-and-start` runs BE+FE |
| `apply-vault-env` | Vault → env files → recreate apps |
| `sync-devops-control-plane` | After you `git push` this repo |
| `github-push-collaboration` | Webhook router (develop branch) |

### ACTION parameter

| ACTION | Builds image? | Deploys? |
|--------|---------------|----------|
| `start` | No | Yes (existing image) |
| `stop` | No | Stops service |
| `restart` | No | Recreates from image |
| `build-and-start` | Yes | Yes |
| `update-from-github` | Yes (after git pull) | Yes |

---

## Daily learning loop

1. **Change DevOps code** (Jenkinsfile, Dockerfile in `docker-devops/`) → push to GitHub DevOps repo → `sync-devops-control-plane` updates jobs.

2. **Deploy app changes** (you did NOT edit app code):
   - Jenkins → `collaboration-backend` → ACTION=`update-from-github`
   - Or push to `develop` on GitHub (webhook)

3. **Practice production pipeline stages** — open any job Console Output and map each stage to the production Jenkinsfile in the app repo.

4. **Secrets** — edit in Vault UI or Secrets Room → run `apply-vault-env`.

---

## Folder map (everything lives here)

```
docker-devops/
├── scripts/
│   ├── reset-server.sh              # Clean Docker on server
│   ├── bootstrap-learning-server.sh # Full setup
│   └── install-from-laptop.sh       # rsync + bootstrap from laptop
├── collaboration/                   # FE + BE stack
│   ├── docker-compose.yml
│   ├── docker/                      # Lab Dockerfiles (not app repo)
│   └── env/                         # Runtime secrets (server only)
├── notification/                    # NES stack (third repo)
├── jenkins/
│   ├── jobs/                        # Pipeline source of truth
│   └── lib/docker-lib.sh            # Shared build/deploy functions
├── vault/                           # HashiCorp Vault
├── secrets-room/                    # Secrets UI
└── registry/                        # Local Docker registry
```

---

## Reset and start over

```bash
bash scripts/reset-server.sh              # stop + prune (keeps DB volumes)
bash scripts/reset-server.sh --wipe-volumes   # full DB/Jenkins wipe
bash scripts/bootstrap-learning-server.sh
```

---

## Rules

- **Never edit** `frontend/Jenkinsfile`, `backend/Jenkinsfile`, or `Notification-and-email-service/Jenkinsfile` for this lab.
- **Never commit** `collaboration/env/*.env`, `jenkins/secrets/*`, or `vault/secrets/*`.
- App repos on the server are **read-only build context** — DevOps owns all automation.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Jenkins job missing | `bash jenkins/bin/sync-jobs.sh` |
| FE build fails (Firebase) | Add `NEXT_PUBLIC_API_KEY` to `collaboration/env/frontend.env` |
| Registry push fails | `docker compose -f registry/docker-compose.yml up -d` |
| Vault sealed | `bash vault/scripts/unseal.sh` |
| Port in use | `bash scripts/reset-server.sh` then bootstrap again |

Jenkins login: see `jenkins/secrets/admin.env` on the server (created at bootstrap).
