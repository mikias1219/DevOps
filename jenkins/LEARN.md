# Jenkins end-to-end (this lab)

Jenkins does **nothing** until something starts a **job**. You should always be able to answer: **who started this job?**

## Who starts a job?

| Cause | Job | What happens |
|---|---|---|
| **You** click **Build with Parameters** | `collaboration-backend` or `collaboration-frontend` | Only that app. You pick `ACTION`. |
| **You** click stack | `collaboration-stack` | `start/stop/restart` = compose only. `build-and-start` / `update-from-github` = **both** apps (you asked for both). |
| GitHub push **develop** on **backend** | `github-push-collaboration` → `collaboration-backend` | `IE-Network-Solutions/selamnew-collaboration-backend` |
| GitHub push **develop** on **frontend** | `github-push-collaboration` → `collaboration-frontend` | `IE-Network-Solutions/selamnew-collaboration-fe` |
| GitHub push to **this DevOps** repo | `sync-devops-control-plane` | Pulls Jenkinsfiles. **Never builds the app.** |

Open any build → **Console Output** → first stage **Why this job ran**.

## ACTION (backend / frontend / stack)

| ACTION | Pull git? | Quality | Docker image | Deploy |
|---|---|---|---|---|
| `start` | no | no | no | compose up current image |
| `stop` | no | no | no | compose stop |
| `restart` | no | no | no | recreate current image |
| `build-and-start` | no | report | **yes** | recreate |
| `update-from-github` | **yes** | report | **yes** | recreate |

**Image build only happens for `build-and-start` or `update-from-github`.**  
If you did not pick those, Jenkins should not build.

## Why backend ran when you did not want it

The webhook job used to start **backend and frontend** when it was not sure which repo was pushed, and when you clicked **Build Now** on the webhook job.

GitHub webhooks (both repos, **push** event, JSON body):

```
http://<SERVER>/generic-webhook-trigger/invoke?token=<collab-token>
```

Token file on the server: `jenkins/secrets/github-webhook-collab-token.txt`  
Content type: **application/json**. Other branches are ignored (job filter: `refs/heads/develop`).

Manual **Build Now** on `github-push-collaboration` does not deploy (no GitHub payload).

## Practice path (recommended)

1. Jenkins → `collaboration-backend` → **Build with Parameters**
2. `ACTION=start` — watch stages; **no** image build
3. `ACTION=build-and-start` — watch Quality → Build and Push → Deploy → Verify
4. `ACTION=update-from-github` — same plus **Pull Latest Changes**
5. Repeat for `collaboration-frontend`
6. Push a Jenkinsfile in this repo → `sync-devops-control-plane` (job XML updates only)

## Do not

- scp Jenkinsfiles onto the server
- click **Build Now** on webhook jobs (they are for GitHub)
- expect DevOps `git push` to rebuild Nest/Next
