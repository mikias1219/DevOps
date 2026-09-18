# Lab Jenkins jobs (production stage parity)

| Lab job | Mirrors production |
|---------|-------------------|
| `Jenkinsfile.collaboration-backend` | `backend/Jenkinsfile` |
| `Jenkinsfile.collaboration-frontend` | `frontend/Jenkinsfile` (core deploy stages only) |
| `Jenkinsfile.collaboration-notification` | `Notification-and-email-service/Jenkinsfile` |
| `Jenkinsfile.github-push-collaboration` | Lab webhook router (no prod equivalent) |

**Full mapping:** [`../../LAB-PRODUCTION-PARITY.md`](../../LAB-PRODUCTION-PARITY.md)  
**Runbook:** [`../../README.md`](../../README.md)

After editing any `Jenkinsfile.*` here:

```bash
bash jenkins/bin/sync-jobs.sh
```

Company Jenkins and app-repo Jenkinsfiles are **not** modified for the lab.
