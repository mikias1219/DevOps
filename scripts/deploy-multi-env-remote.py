#!/usr/bin/env python3
"""Upload DevOps tarball to lab server and run multi-env setup. Requires LAB_SSH_PASSWORD."""
from __future__ import annotations

import base64
import os
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

HOST = os.environ.get("LAB_SERVER", "172.16.50.39")
USER = os.environ.get("LAB_SSH_USER", "ienetworks")
PASSWORD = os.environ.get("LAB_SSH_PASSWORD", "")
LOCAL_DEVOPS = Path(__file__).resolve().parents[1]
REMOTE_DEVOPS = os.environ.get(
    "REMOTE_DEVOPS", f"/home/{USER}/workspace/tools/docker-devops"
)

EXCLUDE_PREFIXES = (
    ".git",
    "collaboration/.env.docker",
    "collaboration/env/",
    "notification/.env.docker",
    "notification/env/",
    "jenkins/secrets/admin.env",
    "jenkins/secrets/github-webhook",
    "vault/secrets/",
)


def should_exclude(name: str) -> bool:
    for ex in EXCLUDE_PREFIXES:
        if name == ex or name.startswith(ex):
            return True
    return False


def build_tarball() -> Path:
    tmp = Path(tempfile.mkstemp(suffix=".tgz")[1])
    with tarfile.open(tmp, "w:gz") as tar:
        for path in LOCAL_DEVOPS.rglob("*"):
            if not path.is_file():
                continue
            rel = path.relative_to(LOCAL_DEVOPS).as_posix()
            if should_exclude(rel):
                continue
            tar.add(path, arcname=rel)
    return tmp


def run_ssh_script(script: str, timeout: float = 600.0) -> int:
    if subprocess.run(["which", "sshpass"], capture_output=True).returncode == 0:
        proc = subprocess.run(
            [
                "sshpass",
                "-p",
                PASSWORD,
                "ssh",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "ConnectTimeout=20",
                f"{USER}@{HOST}",
                "bash -s",
            ],
            input=script.encode(),
            timeout=timeout,
        )
        return proc.returncode

    import shlex

    askpass_fd, askpass_path = tempfile.mkstemp(prefix="lab-askpass-", suffix=".sh")
    os.close(askpass_fd)
    askpass = Path(askpass_path)
    askpass.write_text(f"#!/bin/sh\nexec echo {shlex.quote(PASSWORD)}\n")
    askpass.chmod(0o700)
    env = os.environ.copy()
    env["SSH_ASKPASS"] = str(askpass)
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env["DISPLAY"] = env.get("DISPLAY", ":0")
    try:
        proc = subprocess.run(
            [
                "ssh",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "ConnectTimeout=20",
                f"{USER}@{HOST}",
                "bash -s",
            ],
            input=script.encode(),
            timeout=timeout,
            env=env,
        )
        return proc.returncode
    finally:
        askpass.unlink(missing_ok=True)


def main() -> int:
    if not PASSWORD:
        print("Set LAB_SSH_PASSWORD", file=sys.stderr)
        return 1
    if not LOCAL_DEVOPS.is_dir():
        print(f"Missing {LOCAL_DEVOPS}", file=sys.stderr)
        return 1

    print("Building tarball…")
    tgz = build_tarball()
    print(f"Tarball {tgz} ({tgz.stat().st_size} bytes)", flush=True)
    b64 = base64.b64encode(tgz.read_bytes()).decode()
    tgz.unlink()
    print("Connecting to lab server…", flush=True)

    remote = f"""
set -euo pipefail
DEVOPS='{REMOTE_DEVOPS}'
mkdir -p "$DEVOPS"
python3 - <<'PYB'
import base64, pathlib
b64 = '''{b64}'''
pathlib.Path('/tmp/devops-multi-env.tgz').write_bytes(base64.b64decode(b64))
print('uploaded', len(b64))
PYB
tar xzf /tmp/devops-multi-env.tgz -C "$DEVOPS"
export SERVER_IP='{HOST}'
export SUDO_PASSWORD='{PASSWORD.replace("'", "'\"'\"'")}'
cd "$DEVOPS"
bash scripts/setup-lab-multi-env.sh
bash scripts/configure-lab-communication.sh
if [ -f jenkins/secrets/admin.env ]; then set -a; . jenkins/secrets/admin.env; set +a; fi
export JENKINS_URL=http://127.0.0.1:8080
bash jenkins/bin/sync-jobs.sh
echo "$SUDO_PASSWORD" | sudo -S cp nginx/selamnew-collab.conf /etc/nginx/sites-available/selamnew-collab
echo "$SUDO_PASSWORD" | sudo -S ln -sfn /etc/nginx/sites-available/selamnew-collab /etc/nginx/sites-enabled/selamnew-collab
echo "$SUDO_PASSWORD" | sudo -S rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/selamnew-devops-webhooks 2>/dev/null || true
echo "$SUDO_PASSWORD" | sudo -S nginx -t
echo "$SUDO_PASSWORD" | sudo -S systemctl reload nginx
docker compose -f registry/docker-compose.yml up -d
for tier in test staging production; do
  case "$tier" in
    test) CF=collaboration/docker-compose.yml; EF=collaboration/.env.docker; NF=notification/docker-compose.yml; NEF=notification/.env.docker ;;
    staging) CF=collaboration/docker-compose.staging.yml; EF=collaboration/.env.docker.staging; NF=notification/docker-compose.staging.yml; NEF=notification/.env.docker.staging ;;
    production) CF=collaboration/docker-compose.production.yml; EF=collaboration/.env.docker.production; NF=notification/docker-compose.production.yml; NEF=notification/.env.docker.production ;;
  esac
  [ -f "$EF" ] || continue
  docker compose -f "$CF" --env-file "$EF" up -d db redis elasticsearch 2>/dev/null || true
  [ -f "$NEF" ] && docker compose -f "$NF" --env-file "$NEF" up -d db 2>/dev/null || true
done
bash scripts/verify-lab-staging-parity.sh || true
echo DEPLOY_MULTI_ENV_DONE
"""
    # Chunk b64 if too large for heredoc - 400k chunks
    if len(b64) > 500_000:
        print("Package too large for inline upload; use rsync with sshpass", file=sys.stderr)
        return 1

    return run_ssh_script(remote)


if __name__ == "__main__":
    raise SystemExit(main())
