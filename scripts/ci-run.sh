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
  # Annotations are cut off after a few KB, so lead with the lines that look like errors (skipping
  # warning noise), then the last few lines of output.
  python3 - "${title}" "${log}" <<'PY'
import re, sys
title, path = sys.argv[1], sys.argv[2]
lines = open(path, errors="replace").read().splitlines()
pattern = re.compile(r"error|fail|fatal|cannot|undefined|not found|no such|denied|panic", re.I)
errors = [l for l in lines if pattern.search(l) and "WARNING" not in l][-40:]
text = "\n".join(["-- error lines --", *errors, "-- last lines --", *lines[-15:]])[-3800:]
text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
print("::error title=" + title + " failed::" + text)
PY
fi
rm -f "${log}"
exit "${status}"
