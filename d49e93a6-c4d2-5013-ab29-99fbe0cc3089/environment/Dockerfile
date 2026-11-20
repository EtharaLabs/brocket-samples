# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# Fetch stage: runs on the builder, resolves each checker for the target platform.
FROM --platform=$BUILDPLATFORM node:22-trixie-slim@sha256:68c76cfad89921b927eae28ba21407475e29d0ce450afcdbe70c1532db042b64 AS fetch

ARG TARGETOS
ARG TARGETARCH

COPY install-toolchain.sh /usr/local/sbin/install-toolchain
RUN chmod 755 /usr/local/sbin/install-toolchain
# The frozen JavaScript checker, today's Go build, and one practice Go build. Both Go builds are
# newer than every graded fix, so neither carries a graded bug; the practice build still carries a
# few bugs fixed before today's build, so a tester can be checked against real, fixed divergences.
# No graded build, no TypeScript source tree, and no checker test suite is here.
RUN install-toolchain tsc6 typescript@6.0.3 typescript/bin/tsc \
 && install-toolchain dev typescript@7.1.0-dev.20261113.1 typescript/bin/tsc \
 && install-toolchain practice typescript@7.1.0-dev.20261015.1 typescript/bin/tsc \
 && npm cache clean --force

FROM node:22-trixie-slim@sha256:68c76cfad89921b927eae28ba21407475e29d0ce450afcdbe70c1532db042b64

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates python3 sudo curl git jq xz-utils procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash agent && echo 'agent ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
 && mkdir -p /opt/node22/bin && cp /usr/local/bin/node /opt/node22/bin/node

COPY --from=fetch /opt/ts /opt/ts
# The fetch stage cannot run a target-platform binary, so each checker proves it runs here.
RUN for name in tsc6 dev practice; do /opt/ts/"$name"/bin/tsc --version; done

COPY docs /app/docs
RUN mkdir -p /app/tester && chown -R agent:agent /app
USER agent
WORKDIR /app
