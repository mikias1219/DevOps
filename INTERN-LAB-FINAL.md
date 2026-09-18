# Intern lab — final staging-practice setup

Use this server to practice the **same flow** as company **test/staging** (push `develop` → webhook → Jenkins → build → deploy), without touching **company Jenkins** or editing app-repo `Jenkinsfile`s.

## What “same as staging” means here

| Company (production Jenkins) | Your lab |
|------------------------------|----------|
| Push **`develop`** → test/staging deploy | Push **`develop`** → webhook → lab deploy |
| Pipeline stages in `backend/Jenkinsfile` etc. | **Same stage names** in `collaboration-*` jobs |
| SSH + Docker Hub + Swarm | Host Docker + **127.0.0.1:5001** + **Compose** |
| Users hit test URL | **http://172.16.50.39/** (nginx) |

Deep mapping: [`LAB-PRODUCTION-PARITY.md`](LAB-PRODUCTION-PARITY.md)

## One-time finalize (on VPN)

**From your laptop** (sync DevOps, keep server secrets):

```bash
cd /path/to/DevOps
./scripts/install-from-laptop.sh --skip-build
```

**On the server:**

```bash
cd /home/ienetworks/workspace/tools/docker-devops
bash scripts/finalize-lab-staging-parity.sh
```

That script: URL config → Vault import → nginx → `sync-jobs.sh` → verification.

## GitHub webhooks (required for “same as prod”)

In **each** repo (`selamnew-collaboration-fe`, `selamnew-collaboration-backend`, `notification-and-email-service`):

| Field | Value |
|--------|--------|
| Payload URL | `http://172.16.50.39/generic-webhook-trigger/invoke?token=<collab-token>` |
| Content type | `application/json` |
| Events | **Push** |

Token on server: `jenkins/secrets/github-webhook-collab-token.txt` (often `selamnew-collab-push`).

## Daily practice flow

1. Code on **`develop`** → push.
2. Jenkins: **`github-push-collaboration`** (router) → **`collaboration-backend|frontend|notification`**.
3. Watch stages: Select Environment → … → Verify Deployment.
4. Open app: **http://172.16.50.39/**  
   API: **http://172.16.50.39/api/v1/health**  
   NES: **http://172.16.50.39/notification/api/v1/health**

Manual equivalent: Jenkins → job → **Build with Parameters** → `ACTION=update-from-github`.

## Health check anytime

```bash
bash scripts/verify-lab-staging-parity.sh
```

## UIs (management)

| Tool | URL |
|------|-----|
| Jenkins | http://172.16.50.39:8080 |
| Vault (secrets) | http://172.16.50.39:8200/ui → then Jenkins **`apply-vault-env`** |
| Portainer | https://172.16.50.39:9443 |

## If something breaks

| Symptom | Fix |
|---------|-----|
| Webhook 404 | `bash jenkins/bin/sync-jobs.sh` |
| git pull failed (dirty tree) | Fixed in `git_pull_repo`; reset host checkout if needed |
| Docker Hub timeout on build | Lab Dockerfiles must **not** use `# syntax=docker/dockerfile:1` |
| FE wrong API URL | `bash scripts/configure-lab-communication.sh` → Vault import → **`apply-vault-env`** → rebuild FE |

Company **`staging`** *branch* deploys a different prod path; your lab intentionally mirrors **`develop` → test**, which is the usual intern/staging practice path.
