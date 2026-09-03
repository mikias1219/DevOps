# Jenkins (Collaboration lab)

Jenkins is the **remote control** for host Docker. It does not run Nest or Next itself.

```
jenkins/
  docker-compose.yml     Controller
  Dockerfile             Image (docker CLI + compose plugin)
  plugins.txt
  jobs/                  Pipelines (source of truth)
  lib/                   Shared bash used by every job
  bin/                   Host scripts (sync, setup, trigger)
  templates/             Job XML used by bin/sync-jobs.sh
  init.groovy.d/         First-boot admin
  secrets/               gitignored tokens
```

Pipelines **source** `/var/devops/jenkins/lib/docker-lib.sh`.  
`docker-lib.sh` / `sync-jobs.sh` at this folder root are **shims** (old paths).

## Jobs (keep these)

| Job | Who starts it | What it does |
|---|---|---|
| `collaboration-backend` | You, or GitHub `develop` on the backend repo | Select env → pull (if asked) → quality (report) → image → deploy → smoke |
| `collaboration-frontend` | You, or GitHub `develop` on the frontend repo | Same for Next |
| `collaboration-notification` | You, or GitHub `develop` on NES repo | Same for Notification-and-email-service |
| `collaboration-stack` | You | start/stop/restart compose. `build-and-start` runs **both** app jobs |
| `github-push-collaboration` | GitHub webhook | Router. `develop` + backend repo → backend job only |
| `sync-devops-control-plane` | GitHub webhook on **this** repo | `git pull` + `bin/sync-jobs.sh`. Never builds the app |
| `apply-vault-env` | You / Secrets Room | Vault → `collaboration/env/*.env` |

Removed (redundant): `pull-collaboration-now`, `switch-watch-branch`, housekeeper, `watch-github`.

## ACTION

| ACTION | Image build? |
|---|---|
| `start` `stop` `restart` | no |
| `build-and-start` | yes (local tree) |
| `update-from-github` | yes (after `git pull`) |

## GitHub webhook

Both app repos, **push**, content type **application/json**:

`http://<SERVER>:8080/generic-webhook-trigger/invoke?token=<collab-token>`

Token file: `secrets/github-webhook-collab-token.txt`  
Only branch **`develop`**. Do not use `/github-webhook/`.

GWT 2.4+ uses `PipelineTriggersJobProperty` (not the removed `JobPropertyImpl`).
`bin/sync-jobs.sh` writes that property and injects `triggers { GenericTrigger(...) }`
into the pipeline script so the next build does not wipe webhook config.

DevOps repo uses a **different** token → `sync-devops-control-plane`.

## Register jobs after a Jenkinsfile change

```bash
# on the server, after git pull
bash jenkins/bin/sync-jobs.sh
```

Or push this repo to `main` (webhook). Do not scp Jenkinsfiles.
