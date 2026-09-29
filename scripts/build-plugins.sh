#!/usr/bin/env bash
# Build plugin bundles from src/<name> into out/plugins/ (unsigned).
#
# Usage: scripts/build-plugins.sh [plugin names...]   (default: every plugin in plugins.json)

source "$(dirname "$0")/lib.sh"
require_buildx
require python3

names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  mapfile -t names < <(plugins_field name)
fi

mkdir -p "${OUT_DIR}/plugins"
for name in "${names[@]}"; do
  src="${SRC_DIR}/${name}"
  [[ -d "${src}" ]] || die "missing sources for ${name}; run scripts/fetch-sources.sh ${name}"
  node="$(node_version "${src}")"
  tmp="$(mktemp -d)"
  log "building plugin ${name} (node ${node})"
  # shellcheck disable=SC2046
  docker buildx build \
    --file "${ROOT}/docker/build.Dockerfile" \
    --target plugin \
    --build-context "src=${src}" \
    --build-arg "GO_IMAGE=${GO_IMAGE}" \
    --build-arg "NODE_VERSION=${node}" \
    $(buildx_cache_args "plugin-${name}") \
    --progress plain \
  --output "type=local,dest=${tmp}" \
    "${ROOT}/docker"
  shopt -s nullglob
  bundles=("${tmp}"/*.tar.gz)
  shopt -u nullglob
  [[ ${#bundles[@]} -gt 0 ]] || die "plugin ${name} produced no bundle"
  mv "${bundles[@]}" "${OUT_DIR}/plugins/"
  rm -rf "${tmp}"
done

ls -l "${OUT_DIR}/plugins" >&2
