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

**Default: you click Jenkins.** GitHub does **not** rebuild the app until you set `COLLABORATION_WEBHOOK_DEPLOY=true`.

Read **[jenkins/LEARN.md](jenkins/LEARN.md)** for causes, `ACTION`, and why backend used to start on its own.

```
You (learning):
  Jenkins → collaboration-backend → Build with Parameters → pick ACTION

You (change a Jenkinsfile in this repo):
  git push main → sync-devops-control-plane → jobs update (app is NOT rebuilt)

GitHub auto-deploy (opt-in):
  COLLABORATION_WEBHOOK_DEPLOY=true
  push backend repo  → collaboration-backend only
  push frontend repo → collaboration-frontend only
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
| `collaboration-backend` | **You** click Build with Parameters | API pipeline. Image only if ACTION builds. |
| `collaboration-frontend` | **You** click Build with Parameters | Same for Next |
| `collaboration-stack` | Manual | start/stop compose; build-and-start runs **both** apps |
| `github-push-collaboration` | GitHub push on **develop** | Backend repo → backend job; frontend repo → frontend job |
| `pull-collaboration-now` | Manual | Same as webhook, for a laptop with no public URL |
| `sync-devops-control-plane` | GitHub webhook (devops token) | Pull this repo + rewrite Jenkins jobs |
| `apply-vault-env` | Manual / Secrets Room | Vault → `collaboration/env/*.env`; FE image rebuild |
| `switch-watch-branch` | Manual | Change watched git branch (Collaboration only) |

`ACTION`: `start` | `stop` | `restart` | `build-and-start` | `update-from-github`

Quality **reports** eslint/tests and does not fail the lab (app repo is not ours). Image build + smoke are the gate.

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
