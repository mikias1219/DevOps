# GitHub webhook (Collaboration FE + BE)

Same URL on **both** repos. Jenkins decides which job to run from the JSON body.

## GitHub settings (each repo)

**Repos**
- Backend: `IE-Network-Solutions/selamnew-collaboration-backend`
- Frontend: `IE-Network-Solutions/selamnew-collaboration-fe`

**Settings → Webhooks → Add webhook**

| Field | Value |
|---|---|
| Payload URL | `http://<SERVER_IP>/generic-webhook-trigger/invoke?token=<TOKEN>` |
| Content type | `application/json` |
| Secret | leave empty (token is in the URL) |
| Events | Just the **push** event |
| Active | yes |

`<TOKEN>` is the contents of `jenkins/secrets/github-webhook-collab-token.txt` on the server (default `selamnew-collab-push`).

Do **not** use `/github-webhook/` — that is a different Jenkins plugin. This lab uses **Generic Webhook Trigger**.

## What Jenkins does

| Push | Job |
|---|---|
| `develop` on backend repo | `collaboration-backend` with `ACTION=update-from-github` |
| `develop` on frontend repo | `collaboration-frontend` with `ACTION=update-from-github` |
| any other branch | ignored |

Check: Jenkins → `github-push-collaboration` → last build → **Why this job ran** / **Decide**.
