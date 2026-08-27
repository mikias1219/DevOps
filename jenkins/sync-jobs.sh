#!/usr/bin/env bash
# Shim — job XML used to call jenkins/sync-jobs.sh. Keep this path forever.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/sync-jobs.sh" "$@"
