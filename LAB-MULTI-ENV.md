# Lab: test, staging, and production tiers

One lab server (`172.16.50.39`) runs **three isolated stacks** that mirror company Jenkins branch rules:

| Branch (GitHub) | Lab tier | Jenkins jobs | Public URLs |
|-----------------|----------|--------------|-------------|
| `develop` | **test** | `collaboration-{backend,frontend,notification}-test` | `http://SERVER/` · `/api/` · `/notification/` |
| `staging` | **staging** | `…-staging` | `http://SERVER/staging/…` |
| `production` | **production** | `…-production` | `http://SERVER/production/…` |

Webhook router `github-push-collaboration` starts the matching **named** job (no shared `LAB_TIER` param).

## Jenkins (same stage names as app `Jenkinsfile`s)

1. **Select Environment** — branch → tier + `SECRETS_PATH` (like prod `REMOTE_SERVER` + secrets file).
2. **Fetch Application Variables** — grep `collaboration/lab-secrets/<tier>/.collab-*-env` (like prod SSH grep).
3. **Prepare Repository** → **Pull** → **Remove migrations** (BE/NES) → **Build and Push** → **Deploy** → **Verify**.

Webhook router accepts **`develop`**, **`staging`**, and **`production`** and passes `GIT_BRANCH` + `LAB_TIER` to `collaboration-{backend,frontend,notification}`.

Manual run: choose **LAB_TIER** + **ACTION** (e.g. `build-and-start`).

## Server setup (once)

```bash
cd /home/ienetworks/workspace/tools/docker-devops
bash scripts/setup-lab-multi-env.sh
bash scripts/finalize-lab-staging-parity.sh
```

Git checkouts (separate trees per tier):

```text
.../SelamnewCollaboration/environments/test/backend|frontend|Notification-and-email-service
.../environments/staging/...
.../environments/production/...
```

Vault KV (optional per tier): `secret/collaboration/<tier>/backend|frontend` — falls back to `secret/collaboration/backend` for test.

```bash
LAB_TIER=staging bash scripts/vault-export-collaboration-env.sh both
```

## Compose projects

| Tier | Collaboration compose | Notification compose |
|------|----------------------|------------------------|
| test | `docker-compose.yml` (`collaboration`) | `notification/docker-compose.yml` |
| staging | `docker-compose.staging.yml` | `docker-compose.staging.yml` |
| production | `docker-compose.production.yml` | `docker-compose.production.yml` |

Each tier has its own DB volumes and host ports (see `.env.docker*.example`).
