#!/usr/bin/env bash
# Fetch the server and plugin sources into src/.
#
#   SOURCES=github (default)  clone from GitHub (SERVER_REPO/SERVER_REF, plugins.json repo/ref)
#   SOURCES=local             clone from local checkouts under LOCAL_ROOT (default: parent dir),
#                             using committed work only: by default each checkout's current
#                             branch (HEAD), never uncommitted changes
#
# Usage: scripts/fetch-sources.sh [server] [plugin names...]   (default: everything)
# Refs can be overridden per component: SERVER_REF=..., REF_<NAME>=... (e.g. REF_CALLS=main).

source "$(dirname "$0")/lib.sh"
require git python3

SOURCES="${SOURCES:-github}"
LOCAL_ROOT="${LOCAL_ROOT:-$(cd "${ROOT}/.." && pwd)}"

clone() {
  local name="$1" url="$2" ref="$3" dest="${SRC_DIR}/$1"
  log "fetching ${name} (${url} @ ${ref})"
  rm -rf "${dest}"
  git init -q "${dest}"
  git -C "${dest}" remote add origin "${url}"
  # Works for branches, tags and full commit SHAs.
  git -C "${dest}" fetch -q --depth 1 origin "${ref}"
  git -C "${dest}" checkout -q --detach FETCH_HEAD
  git -C "${dest}" log -1 --format="    %h %s" >&2
}

source_url() {
  local repo="$1" local_dir="$2"
  if [[ "${SOURCES}" == "local" ]]; then
    [[ -d "${LOCAL_ROOT}/${local_dir}" ]] || die "local checkout not found: ${LOCAL_ROOT}/${local_dir}"
    echo "file://${LOCAL_ROOT}/${local_dir}"
  else
    echo "https://github.com/${repo}.git"
  fi
}

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  mapfile -t targets < <(echo server; plugins_field name)
fi

mkdir -p "${SRC_DIR}"
for target in "${targets[@]}"; do
  if [[ "${target}" == "server" ]]; then
    ref="${SERVER_REF}"
    [[ "${SOURCES}" == "local" ]] && ref="${SERVER_REF_LOCAL:-HEAD}"
    clone server "$(source_url "${SERVER_REPO}" "${SERVER_LOCAL}")" "${ref}"
  else
    ref_var="REF_$(echo "${target}" | tr '[:lower:]-' '[:upper:]_')"
    default_ref="$(plugin_field "${target}" ref)"
    [[ "${SOURCES}" == "local" ]] && default_ref=HEAD
    ref="${!ref_var:-${default_ref}}"
    clone "${target}" "$(source_url "$(plugin_field "${target}" repo)" "$(plugin_field "${target}" local)")" "${ref}"
  fi
done
