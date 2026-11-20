# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# Fetch stage: runs on the builder, resolves every graded checker for the target platform.
FROM --platform=$BUILDPLATFORM node:22-trixie-slim@sha256:68c76cfad89921b927eae28ba21407475e29d0ce450afcdbe70c1532db042b64 AS fetch

ARG TARGETOS
ARG TARGETARCH

COPY install-toolchain.sh /usr/local/sbin/install-toolchain
RUN chmod 755 /usr/local/sbin/install-toolchain
# The baseline JavaScript checker and today's Go build, as in the agent image.
RUN install-toolchain tsc6 typescript@6.0.3 typescript/bin/tsc \
 && install-toolchain dev typescript@7.1.0-dev.20261113.1 typescript/bin/tsc
# The graded Go builds: the pre and post build of every window. None reaches the agent image.
RUN for b in 20260423.1 20260424.1 20260430.1 20260501.1 20260505.1 20260506.1 20260515.1 20260516.1 20260518.1 20260519.1; do \
      install-toolchain tsgo-$b @typescript/native-preview@7.0.0-dev.$b @typescript/native-preview/bin/tsgo.js || exit 1; done
RUN for b in 20260721.1 20260722.1 20261013.1 20261014.1; do \
      install-toolchain tsgo-$b typescript@7.1.0-dev.$b typescript/bin/tsc || exit 1; done

FROM node:22-trixie-slim@sha256:68c76cfad89921b927eae28ba21407475e29d0ce450afcdbe70c1532db042b64

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates python3 sudo curl git jq xz-utils procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash agent && echo 'agent ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
 && mkdir -p /opt/node22/bin && cp /usr/local/bin/node /opt/node22/bin/node

COPY --from=fetch /opt/ts /opt/ts
# The fetch stage cannot run a target-platform binary, so every checker proves it runs here.
RUN for launcher in /opt/ts/*/bin/tsc; do "$launcher" --version; done

COPY grader /tests/grader
COPY test.sh /tests/test.sh
RUN mkdir -p /app && chmod 755 /tests/test.sh
WORKDIR /app
