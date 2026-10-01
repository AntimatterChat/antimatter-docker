#!/usr/bin/env bash
# Shared helpers for the Antimatter build scripts. Source it; don't run it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${SRC_DIR:-${ROOT}/src}"
OUT_DIR="${OUT_DIR:-${ROOT}/out}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# The image variant to build (see variants/): selects the image name, the server ref and, through
# plugins.json, which plugins are built and from which refs.
export VARIANT="${VARIANT:-stable}"
[[ -f "${ROOT}/variants/${VARIANT}.env" ]] || die "unknown VARIANT ${VARIANT} (no variants/${VARIANT}.env)"

# Load variants/<VARIANT>.env, then build.env, without overriding variables already set in the
# environment (or by the variant), remembering which values are defaults (see is_default).
BUILD_ENV_DEFAULTS=" "
load_env_file() {
  local key value
  while IFS='=' read -r key value; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    if [[ -z "${!key+x}" ]]; then
      export "${key}=${value}"
      BUILD_ENV_DEFAULTS+="${key} "
    fi
  done < "$1"
}
load_env_file "${ROOT}/variants/${VARIANT}.env"
load_env_file "${ROOT}/build.env"

# is_default <VAR>: true when VAR holds its variant or build.env default rather than an explicit
# value.
is_default() { [[ "${BUILD_ENV_DEFAULTS}" == *" $1 "* ]]; }

require() {
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "missing required command: ${cmd}"
  done
}

require_buildx() {
  require docker
  docker buildx version >/dev/null 2>&1 || die "docker buildx is required (install the docker-buildx plugin)"
}

# Plugin entries of plugins.json for VARIANT: entries with a "variants" list only belong to the
# variants it names, and "overrides": {"<variant>": {...}} replaces fields (e.g. "ref") for one
# variant.
PLUGINS_PY='import json, sys
def plugins(path, variant):
    for p in json.load(open(path)):
        if variant in p.get("variants", [variant]):
            yield {**p, **p.get("overrides", {}).get(variant, {})}
'

# plugins_field <field>: prints the field of every plugin of VARIANT, one per line.
plugins_field() {
  python3 -c "${PLUGINS_PY}"'
for p in plugins(sys.argv[1], sys.argv[2]):
    print(p[sys.argv[3]])' "${ROOT}/plugins.json" "${VARIANT}" "$1"
}

# plugin_field <name> <field>: the field of one plugin of VARIANT.
plugin_field() {
  python3 -c "${PLUGINS_PY}"'
for p in plugins(sys.argv[1], sys.argv[2]):
    if p["name"] == sys.argv[3]:
        print(p[sys.argv[4]]); break
else:
    sys.exit("plugin " + sys.argv[3] + " is not part of the " + sys.argv[2] + " variant")' \
    "${ROOT}/plugins.json" "${VARIANT}" "$1" "$2"
}

# node_version <dir>: the Node.js version pinned by the checkout's .nvmrc. Partial versions
# (e.g. "20.11") resolve to the newest matching release listed on nodejs.org.
node_version() {
  local dir="$1" file version=""
  for file in "${dir}/.nvmrc" "${dir}/webapp/.nvmrc"; do
    if [[ -f "${file}" ]]; then
      version="$(tr -d ' \r\n' < "${file}" | sed 's/^v//')"
      break
    fi
  done
  [[ -n "${version}" ]] || die "no .nvmrc found in ${dir}"
  if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${version}"
    return
  fi
  python3 - "${version}" <<'PY' || die "can't resolve Node.js version ${version}"
import json, sys, urllib.request
want = sys.argv[1].split(".")
with urllib.request.urlopen("https://nodejs.org/dist/index.json", timeout=30) as resp:
    releases = json.load(resp)
for release in releases:  # newest first
    parts = release["version"].lstrip("v").split(".")
    if parts[:len(want)] == want:
        print(".".join(parts))
        break
else:
    sys.exit(1)
PY
}

# buildx_cache_args <scope>: optional GitHub Actions cache for BuildKit (set BUILDX_CACHE=gha).
buildx_cache_args() {
  if [[ "${BUILDX_CACHE:-}" == "gha" ]]; then
    echo "--cache-from type=gha,scope=$1 --cache-to type=gha,mode=max,scope=$1"
  fi
}
