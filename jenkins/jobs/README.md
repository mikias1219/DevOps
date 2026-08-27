# Pipelines

One file per Jenkins job. `bin/sync-jobs.sh` reads these files and POSTs them to Jenkins.

| File | Jenkins job |
|---|---|
| `Jenkinsfile.collaboration-backend` | collaboration-backend |
| `Jenkinsfile.collaboration-frontend` | collaboration-frontend |
| `Jenkinsfile.collaboration-stack` | collaboration-stack |
| `Jenkinsfile.github-push-collaboration` | github-push-collaboration |
| `Jenkinsfile.sync-devops-control-plane` | sync-devops-control-plane |
| `Jenkinsfile.apply-vault-env` | apply-vault-env |

First stage of the app jobs is **Why this job ran** (manual vs webhook).
