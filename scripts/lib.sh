#!/usr/bin/env bash
# Shared helpers for the Antimatter build scripts. Source it; don't run it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${SRC_DIR:-${ROOT}/src}"
OUT_DIR="${OUT_DIR:-${ROOT}/out}"

# Load build.env without overriding variables already set in the environment, remembering which
# values are build.env defaults (see is_default).
BUILD_ENV_DEFAULTS=" "
while IFS='=' read -r key value; do
  [[ -z "${key}" || "${key}" == \#* ]] && continue
  if [[ -z "${!key+x}" ]]; then
    export "${key}=${value}"
    BUILD_ENV_DEFAULTS+="${key} "
  fi
done < "${ROOT}/build.env"

# is_default <VAR>: true when VAR holds its build.env default rather than an explicit value.
is_default() { [[ "${BUILD_ENV_DEFAULTS}" == *" $1 "* ]]; }

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "missing required command: ${cmd}"
  done
}

require_buildx() {
  require docker
  docker buildx version >/dev/null 2>&1 || die "docker buildx is required (install the docker-buildx plugin)"
}

# plugins_field <field>: prints the field of every entry in plugins.json, one per line.
plugins_field() {
  python3 -c 'import json,sys; [print(p[sys.argv[2]]) for p in json.load(open(sys.argv[1]))]' \
    "${ROOT}/plugins.json" "$1"
}

# plugin_field <name> <field>
plugin_field() {
  python3 -c 'import json,sys
for p in json.load(open(sys.argv[1])):
    if p["name"] == sys.argv[2]:
        print(p[sys.argv[3]]); break
else:
    sys.exit("unknown plugin: " + sys.argv[2])' "${ROOT}/plugins.json" "$1" "$2"
}

# node_version <dir>: the Node.js version pinned by the checkout's .nvmrc.
node_version() {
  local dir="$1" file
  for file in "${dir}/.nvmrc" "${dir}/webapp/.nvmrc"; do
    if [[ -f "${file}" ]]; then
      tr -d ' \r\n' < "${file}" | sed 's/^v//'
      return
    fi
  done
  die "no .nvmrc found in ${dir}"
}

# buildx_cache_args <scope>: optional GitHub Actions cache for BuildKit (set BUILDX_CACHE=gha).
buildx_cache_args() {
  if [[ "${BUILDX_CACHE:-}" == "gha" ]]; then
    echo "--cache-from type=gha,scope=$1 --cache-to type=gha,mode=max,scope=$1"
  fi
}
