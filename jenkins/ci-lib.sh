# Shim so `. /var/devops/jenkins/ci-lib.sh` still works.
# shellcheck disable=SC1091
_HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "${_HERE}/lib/ci-lib.sh"
