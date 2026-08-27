# Shim so `. /var/devops/jenkins/docker-lib.sh` still works.
# shellcheck disable=SC1091
_HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "${_HERE}/lib/docker-lib.sh"
