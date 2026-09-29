#!/usr/bin/env bash
# Build the server (web app + linux amd64/arm64 binaries) from src/server into
# out/server/antimatter-linux-<arch>.tar.gz.
#
# Usage: BUILD_NUMBER=1.2.3 scripts/build-server.sh

source "$(dirname "$0")/lib.sh"
require_buildx

src="${SRC_DIR}/server"
[[ -d "${src}" ]] || die "missing server sources; run scripts/fetch-sources.sh server"
node="$(node_version "${src}")"
build_number="${BUILD_NUMBER:-$(git -C "${src}" rev-parse --short HEAD 2>/dev/null || echo dev)}"
tmp="$(mktemp -d)"

log "building server ${build_number} (node ${node})"
# shellcheck disable=SC2046
docker buildx build \
  --file "${ROOT}/docker/build.Dockerfile" \
  --target server \
  --build-context "src=${src}" \
  --build-arg "GO_IMAGE=${GO_IMAGE}" \
  --build-arg "NODE_VERSION=${node}" \
  --build-arg "BUILD_NUMBER=${build_number}" \
  --build-arg "BUILD_NODE_OPTIONS=${BUILD_NODE_OPTIONS}" \
  $(buildx_cache_args server) \
  --progress plain \
  --output "type=local,dest=${tmp}" \
  "${ROOT}/docker"

mkdir -p "${OUT_DIR}/server"
for arch in amd64 arm64; do
  shopt -s nullglob
  matches=("${tmp}"/*-linux-"${arch}".tar.gz)
  shopt -u nullglob
  [[ ${#matches[@]} -eq 1 ]] || die "expected one linux-${arch} server tarball, found ${#matches[@]}"
  mv "${matches[0]}" "${OUT_DIR}/server/antimatter-linux-${arch}.tar.gz"
done
rm -rf "${tmp}"

ls -l "${OUT_DIR}/server" >&2
