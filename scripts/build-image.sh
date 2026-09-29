#!/usr/bin/env bash
# Build the runtime image from out/server/*.tar.gz and the signed bundles in out/plugins/.
#
#   PUSH=1          push to the registry (multi-platform, PLATFORMS from build.env)
#   PUSH unset      load a single-platform image into the local docker (host platform)
#   TAGS            space-separated tags (default: "<IMAGE>:dev")
#   EXTRA_ARGS      extra arguments for docker buildx build (e.g. labels)

source "$(dirname "$0")/lib.sh"
require_buildx

ls "${OUT_DIR}"/server/antimatter-linux-*.tar.gz >/dev/null 2>&1 || die "no server tarballs; run scripts/build-server.sh"
for bundle in "${OUT_DIR}"/plugins/*.tar.gz; do
  [[ -f "${bundle}.sig" ]] || die "unsigned plugin bundle ${bundle}; run scripts/sign-plugins.sh"
done

tags="${TAGS:-${IMAGE}:dev}"
tag_args=()
for tag in ${tags}; do tag_args+=(--tag "${tag}"); done

if [[ -n "${PUSH:-}" ]]; then
  output=(--platform "${PLATFORMS}" --push)
else
  output=(--load)
fi

log "building image ${tags}"
# shellcheck disable=SC2086
docker buildx build \
  --file "${ROOT}/Dockerfile" \
  "${tag_args[@]}" \
  "${output[@]}" \
  ${EXTRA_ARGS:-} \
  "${ROOT}"
