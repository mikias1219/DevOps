Jenkins secrets (NEVER commit real values)

Required files on the server:
  admin.env                         JENKINS_ADMIN_USER / JENKINS_ADMIN_PASS
  github-webhook-token.txt          token for sync-devops-control-plane webhook
  github-webhook-collab-token.txt   token for github-push-collaboration webhook
  github-webhook-secret.txt         optional GitHub HMAC secret (documentation)

Copy from *.example files, then chmod 600.

Generate a token:
  openssl rand -hex 16
