#!/usr/bin/env bash
# Run a build command in CI, keeping its full output in the job log and, if it fails, publishing
# the end of that output as an error annotation (annotations are readable without admin rights,
# unlike job logs).
#
# Usage: scripts/ci-run.sh <title> <command> [args...]

set -uo pipefail

title="$1"
shift
log="$(mktemp)"

"$@" 2>&1 | tee "${log}"
status=${PIPESTATUS[0]}

if [[ ${status} -ne 0 ]]; then
  tail -n "${CI_ERROR_LINES:-150}" "${log}" | python3 -c '
import sys
text = sys.stdin.read().replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
print("::error title=" + sys.argv[1] + " failed::" + text)' "${title}"
fi
rm -f "${log}"
exit "${status}"
