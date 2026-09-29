#!/usr/bin/env bash
# Fetch, build, sign and package everything into a local image.
#
#   SOURCES=local scripts/build-all.sh     build from your local checkouts (committed refs)
#   scripts/build-all.sh                   build from GitHub
#   PUSH=1 TAGS="ghcr.io/antimatterchat/antimatter:1.0.0" scripts/build-all.sh

source "$(dirname "$0")/lib.sh"

"${ROOT}/scripts/fetch-sources.sh"
rm -rf "${OUT_DIR}"
"${ROOT}/scripts/build-plugins.sh"
"${ROOT}/scripts/build-server.sh"
"${ROOT}/scripts/sign-plugins.sh"
"${ROOT}/scripts/build-image.sh"
