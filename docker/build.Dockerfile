# syntax=docker/dockerfile:1.7
#
# Toolchain used to compile Antimatter and its plugins. The sources come from the named build
# context "src" (docker buildx build --build-context src=<dir>); results are exported with
# --output type=local. Targets:
#   plugin  -> the plugin bundle(s) produced by `make dist` (dist/*.tar.gz)
#   server  -> the server release tarballs for linux amd64 and arm64

ARG GO_IMAGE=golang:1.27-bookworm

FROM ${GO_IMAGE} AS toolchain
ARG NODE_VERSION
RUN test -n "${NODE_VERSION}" || (echo "NODE_VERSION build arg is required" && exit 1)

# Native build dependencies needed by some npm packages (image optimisers, canvas, node-gyp).
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  autoconf automake build-essential ca-certificates curl git libtool nasm pkg-config python3 xz-utils \
  libpng-dev libjpeg-dev libgif-dev libcairo2-dev libpango1.0-dev librsvg2-dev \
  && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)"; \
  case "${arch}" in amd64) node_arch=x64 ;; arm64) node_arch=arm64 ;; *) echo "unsupported arch ${arch}"; exit 1 ;; esac; \
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
  | tar -xJ -C /usr/local --strip-components=1 \
  && node --version && npm --version

ENV GOTOOLCHAIN=auto \
  CI=true \
  GOFLAGS=-buildvcs=false

# ---------------------------------------------------------------------------------------------
FROM toolchain AS plugin-build
COPY --from=src . /src
WORKDIR /src
RUN --mount=type=cache,target=/go/pkg/mod \
  --mount=type=cache,target=/root/.cache/go-build \
  --mount=type=cache,target=/root/.npm \
  make dist \
  && ls -l dist/*.tar.gz

FROM scratch AS plugin
COPY --from=plugin-build /src/dist/*.tar.gz /

# ---------------------------------------------------------------------------------------------
FROM toolchain AS server-build
ARG BUILD_NUMBER=dev
ARG BUILD_NODE_OPTIONS=--max-old-space-size=6144
COPY --from=src . /src

WORKDIR /src/webapp
RUN --mount=type=cache,target=/root/.npm \
  NODE_OPTIONS="${BUILD_NODE_OPTIONS}" make dist

WORKDIR /src/server
# PLUGIN_PACKAGES is empty: the prepackaged plugins are built and signed separately and added
# to the image by the runtime Dockerfile.
RUN --mount=type=cache,target=/go/pkg/mod \
  --mount=type=cache,target=/root/.cache/go-build \
  make build-linux BUILD_NUMBER="${BUILD_NUMBER}" \
  && make package-linux BUILD_NUMBER="${BUILD_NUMBER}" PLUGIN_PACKAGES= \
  && ls -l dist/*-linux-*.tar.gz

FROM scratch AS server
COPY --from=server-build /src/server/dist/*-linux-*.tar.gz /
