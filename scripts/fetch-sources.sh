#!/usr/bin/env bash
# Fetch the server and plugin sources into src/.
#
#   SOURCES=github (default)  clone from GitHub (SERVER_REPO/SERVER_REF, plugins.json repo/ref)
#   SOURCES=local             clone from local checkouts under LOCAL_ROOT (default: parent dir),
#                             using committed work only: by default each checkout's current
#                             branch (HEAD), never uncommitted changes
#
# Usage: scripts/fetch-sources.sh [server] [plugin names...]   (default: everything)
#
# Which ref each component is built from, first match wins:
#   1. an explicit ref:  SERVER_REF=... / SERVER_REF_LOCAL=... for the server;
#                        REF_<NAME>=... (e.g. REF_CALLS=new-ui) or an entry of
#                        PLUGIN_REFS="calls=new-ui boards=my-fix" for a plugin
#   2. PREFER_REF=...    used for every component whose repository has that branch or tag,
#                        e.g. PREFER_REF=new-ui builds the new-ui branch of the server and of the
#                        plugins that have one, and the default ref everywhere else
#   3. the default:      build.env SERVER_REF / plugins.json ref (HEAD with SOURCES=local)

source "$(dirname "$0")/lib.sh"
require git python3

SOURCES="${SOURCES:-github}"
LOCAL_ROOT="${LOCAL_ROOT:-$(cd "${ROOT}/.." && pwd)}"
PREFER_REF="${PREFER_REF:-}"
PLUGIN_REFS="${PLUGIN_REFS:-}"

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

# ref_exists <url> <ref>: whether the repository has that branch or tag (commit SHAs are assumed
# to exist).
ref_exists() {
  local url="$1" ref="$2"
  [[ "${ref}" =~ ^[0-9a-f]{40}$ ]] && return 0
  git ls-remote --exit-code "${url}" "refs/heads/${ref}" "refs/tags/${ref}" >/dev/null 2>&1
}

# plugin_ref_from_list <name>: the ref PLUGIN_REFS gives the plugin, if any.
plugin_ref_from_list() {
  local entry
  for entry in ${PLUGIN_REFS//,/ }; do
    [[ "${entry%%=*}" == "$1" ]] && { echo "${entry#*=}"; return; }
  done
  return 0
}

# resolve_ref <url> <explicit ref or empty> <default ref>
resolve_ref() {
  local url="$1" explicit="$2" default="$3"
  if [[ -n "${explicit}" ]]; then
    echo "${explicit}"
  elif [[ -n "${PREFER_REF}" ]] && ref_exists "${url}" "${PREFER_REF}"; then
    echo "${PREFER_REF}"
  else
    echo "${default}"
  fi
}

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  mapfile -t targets < <(echo server; plugins_field name)
fi

# Reject PLUGIN_REFS entries naming unknown plugins, so a typo doesn't silently build the default.
known=" $(plugins_field name | tr '\n' ' ')"
for entry in ${PLUGIN_REFS//,/ }; do
  [[ "${entry}" == *=* && "${known}" == *" ${entry%%=*} "* ]] || die "bad PLUGIN_REFS entry: ${entry}"
done

mkdir -p "${SRC_DIR}"
for target in "${targets[@]}"; do
  if [[ "${target}" == "server" ]]; then
    url="$(source_url "${SERVER_REPO}" "${SERVER_LOCAL}")"
    if [[ "${SOURCES}" == "local" ]]; then
      explicit="${SERVER_REF_LOCAL:-}" default=HEAD
    else
      explicit="" default="${SERVER_REF}"
      is_default SERVER_REF || explicit="${SERVER_REF}"
    fi
    clone server "${url}" "$(resolve_ref "${url}" "${explicit}" "${default}")"
  else
    url="$(source_url "$(plugin_field "${target}" repo)" "$(plugin_field "${target}" local)")"
    ref_var="REF_$(echo "${target}" | tr '[:lower:]-' '[:upper:]_')"
    explicit="${!ref_var:-$(plugin_ref_from_list "${target}")}"
    default="$(plugin_field "${target}" ref)"
    [[ "${SOURCES}" == "local" ]] && default=HEAD
    clone "${target}" "${url}" "$(resolve_ref "${url}" "${explicit}" "${default}")"
  fi
done
