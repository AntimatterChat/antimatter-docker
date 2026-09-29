# syntax=docker/dockerfile:1.7
#
# SPDX-License-Identifier: AGPL-3.0-only
# Adapted from server/build/Dockerfile of the Mattermost server,
# Copyright (c) 2015-present Mattermost, Inc. Modifications Copyright 2026 The Antimatter
# contributors. See NOTICE and LICENSE-AGPL-3.0.
#
# Antimatter runtime image. Built by scripts/build-image.sh from:
#   out/server/antimatter-linux-<arch>.tar.gz   server release tarballs (scripts/build-server.sh)
#   out/plugins/*.tar.gz + *.tar.gz.sig          signed plugin bundles (scripts/sign-plugins.sh)

# First stage: Debian 12, matching the distroless base's C library, with the document-processing
# tools used to extract text from uploaded files for search.
FROM debian:bookworm-slim AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG PUID=2000
ARG PGID=2000

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  ca-certificates \
  media-types \
  mailcap \
  unrtf \
  wv \
  poppler-utils \
  tidy \
  tzdata \
  && rm -rf /var/lib/apt/lists/*

# Collect the shared libraries the tools need, except the C runtime the distroless base provides.
RUN mkdir -p /opt/doc-libs \
  && for tool in /usr/bin/pdftotext /usr/bin/wvWare /usr/bin/unrtf /usr/bin/tidy; do ldd "${tool}"; done \
  | awk '/=> \// {print $3}' | sort -u \
  | grep -vE '/(libc|libm|libdl|libpthread|librt|libresolv|ld-linux[^/]*)\.so' \
  | xargs -r -I{} cp -L {} /opt/doc-libs/

COPY out/server/antimatter-linux-${TARGETARCH}.tar.gz /tmp/server.tar.gz
COPY out/plugins/ /tmp/plugins/

# The release tarball has a single top-level directory; install its content as /antimatter.
# Until the server's binaries are renamed, antimatter/amctl are provided as links to them.
RUN mkdir -p /tmp/server \
  && tar -xzf /tmp/server.tar.gz -C /tmp/server \
  && mv /tmp/server/* /antimatter \
  && mkdir -p /antimatter/data /antimatter/logs /antimatter/plugins /antimatter/client/plugins /antimatter/prepackaged_plugins \
  && cp /tmp/plugins/*.tar.gz /tmp/plugins/*.tar.gz.sig /antimatter/prepackaged_plugins/ \
  && if [ ! -e /antimatter/bin/antimatter ]; then ln -s mattermost /antimatter/bin/antimatter; fi \
  && if [ ! -e /antimatter/bin/amctl ]; then ln -s mmctl /antimatter/bin/amctl; fi \
  && test -x /antimatter/bin/antimatter && test -x /antimatter/bin/amctl \
  && mkdir -p /antimatter/.postgresql && chmod 700 /antimatter/.postgresql \
  && chown -R ${PUID}:${PGID} /antimatter \
  && rm -rf /tmp/server /tmp/server.tar.gz /tmp/plugins

# Final stage: distroless for a minimal attack surface.
FROM gcr.io/distroless/base-debian12

ENV PATH="/antimatter/bin:${PATH}"
# The server still reads its settings from MM_* variables; AM_* aliases come with the server
# rebrand.
ENV MM_SERVICESETTINGS_ENABLELOCALMODE="true"
ENV MM_INSTALL_TYPE="docker"

COPY --from=builder /etc/mime.types /etc
COPY --from=builder --chown=2000:2000 /etc/ssl/certs /etc/ssl/certs

# Document-processing utilities and their libraries.
COPY --from=builder /usr/bin/pdftotext /usr/bin/pdftotext
COPY --from=builder /usr/bin/wvText /usr/bin/wvText
COPY --from=builder /usr/bin/wvWare /usr/bin/wvWare
COPY --from=builder /usr/bin/unrtf /usr/bin/unrtf
COPY --from=builder /usr/bin/tidy /usr/bin/tidy
COPY --from=builder /usr/share/wv /usr/share/wv
COPY --from=builder /opt/doc-libs/ /usr/local/lib/doc-tools/
ENV LD_LIBRARY_PATH=/usr/local/lib/doc-tools

COPY --from=builder --chown=2000:2000 /antimatter /antimatter
COPY passwd /etc/passwd

USER antimatter

HEALTHCHECK --interval=30s --timeout=10s \
  CMD ["/antimatter/bin/amctl", "system", "status", "--local"]

WORKDIR /antimatter
CMD ["/antimatter/bin/antimatter"]

# 8065: web/API, 8067: metrics, 8074: cluster gossip, 8443: Calls (UDP and TCP)
EXPOSE 8065 8067 8074 8443/udp 8443/tcp

VOLUME ["/antimatter/data", "/antimatter/logs", "/antimatter/config", "/antimatter/plugins", "/antimatter/client/plugins"]
