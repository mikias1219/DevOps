# DevOps lab — Collaboration only

This repo is the **control plane**. It does **not** contain Nest/Next source.

| Repo | What it is | Do we edit it? |
|---|---|---|
| `mikias1219/DevOps` (this folder) | Compose, Jenkinsfiles, Vault, registry | **Yes — this is the lab** |
| Collaboration backend | Nest API | **No** (production Jenkinsfile stays) |
| Collaboration frontend | Next app | **No** (production Jenkinsfile stays) |

Production `frontend/Jenkinsfile` is the **stage shape** we copy (select env → fetch vars → pull → build/push image → deploy → verify). The lab uses a **local registry + Compose** instead of Docker Hub + Swarm, on one VM (`172.16.50.39`).

---

## Daily learning loop

```
1. Change app code in backend/ or frontend/  (separate git repos)
2. git push develop
3. GitHub webhook → Nginx :80 → github-push-collaboration
4. That job starts collaboration-backend and/or collaboration-frontend
5. Stages: Select env → fetch vars → pull → quality → build → push 127.0.0.1:5001 → compose recreate → smoke

Change a Jenkinsfile here:
1. git push main (this DevOps repo)
2. Webhook → sync-devops-control-plane
3. git pull /var/devops → bin/sync-jobs.sh → Jenkins job XML updated
   Do not scp Jenkinsfiles.
```

---

## Folder map

```
collaboration/          Compose + docker-devops-owned Dockerfiles + env/
registry/               Local registry :5001 (Build+Push practice)
jenkins/
  jobs/                 Jenkinsfiles (source of truth)
  lib/docker-lib.sh     git / quality / build / deploy / smoke
  bin/sync-jobs.sh       Registers jobs from jobs/*.  Deletes housekeeper jobs.
  templates/            Job XML skeletons
jenkins/sync-jobs.sh    Shim (old webhook job still calls this path)
vault/  secrets-room/    Secrets on the server
portainer/  nginx/       Ops UI + webhook proxy
```

---

## Jenkins jobs

| Job | Trigger | What it does |
|---|---|---|
| `collaboration-backend` | Manual `ACTION` or webhook router | Production-shaped pipeline for the API |
| `collaboration-frontend` | same | Same for Next |
| `collaboration-stack` | Manual | start/stop whole compose, or trigger both app jobs |
| `github-push-collaboration` | GitHub webhook (collab token) | Routes to FE and/or BE `ACTION=update-from-github` |
| `pull-collaboration-now` | Manual | Same as webhook, for a laptop with no public URL |
| `sync-devops-control-plane` | GitHub webhook (devops token) | Pull this repo + rewrite Jenkins jobs |
| `apply-vault-env` | Manual / Secrets Room | Vault → `collaboration/env/*.env`; FE image rebuild |
| `switch-watch-branch` | Manual | Change watched git branch (Collaboration only) |

`ACTION`: `start` | `stop` | `restart` | `build-and-start` | `update-from-github`

Quality uses `npx eslint` **without `--fix`** (app `npm run lint` would dirty git). Backend also runs `npm test`. Set `SKIP_QUALITY=true` only as an emergency bypass.

---

## First time on a machine

```bash
cp collaboration/.env.docker.example collaboration/.env.docker   # set COLLABORATION_SOURCE
./scripts/start-all.sh
# Jenkins UI → collaboration-backend + collaboration-frontend
#              ACTION=build-and-start
```

On the server, GitHub webhooks must already point at:

- `http://<host>/generic-webhook-trigger/invoke?token=<devops-token>` → `sync-devops-control-plane`
- `http://<host>/generic-webhook-trigger/invoke?token=<collab-token>` → `github-push-collaboration`

Do **not** rotate those token files unless you also update GitHub.

---

## Cutover note (live VM)

After you push this commit:

1. `sync-devops-control-plane` pulls the repo and rewrites jobs (housekeeper jobs are deleted).
2. Running FE/BE containers stay on the **old** bind-mount until you recreate them.
3. Run `collaboration-backend` and `collaboration-frontend` with `ACTION=build-and-start` so images exist in `127.0.0.1:5001`.
4. Then `ACTION=start` (or one `up --no-deps --force-recreate`) so compose switches to images.
5. Rollback: `git checkout HEAD~1 -- collaboration/docker-compose.yml` and recreate only `backend` `frontend`. Do not `compose down` (that stops Postgres).

---

## Rules

- Apps run in Docker. Do not `npm run dev` on the host for this lab.
- Do not edit `frontend/` or `backend/` from this repo (including their production Jenkinsfiles).
- Secrets stay in `jenkins/secrets/`, `collaboration/env/`, Vault — never GitHub.
- Jenkins is a remote control for **host** Docker via `/var/run/docker.sock`.
