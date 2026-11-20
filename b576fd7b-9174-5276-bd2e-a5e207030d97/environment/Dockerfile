# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Fetch stage: runs on the builder, resolves each checker for the target platform. The TypeScript 7
# development build ships its Go executable as a per-platform optional dependency, so this stage
# resolves against TARGETOS/TARGETARCH rather than the builder's own platform; npm names an
# architecture the way Node does, where amd64 is x64. --ignore-scripts keeps it cross-safe.
FROM --platform=$BUILDPLATFORM node:26.13.0-bookworm-slim@sha256:add5c17c14752c54d2f3d519ec46a3815684d41c33f198bcb09fb998f7dcbf68 AS compilers
ARG TARGETOS
ARG TARGETARCH
# Security boundary: only the frozen reference and one public development build, never a graded build.
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) npm_cpu=x64 ;; \
      arm64) npm_cpu=arm64 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    for spec in reference:typescript@6.0.3 dev:typescript@7.1.0-dev.20261113.1; do \
      npm install --prefix "/opt/compilers/${spec%%:*}" --ignore-scripts --no-audit --no-fund \
        --os "$TARGETOS" --cpu "$npm_cpu" "${spec#*:}"; \
    done; \
    rm -rf /root/.npm

FROM node:26.13.0-bookworm-slim@sha256:add5c17c14752c54d2f3d519ec46a3815684d41c33f198bcb09fb998f7dcbf68
ENV GOMAXPROCS=2
COPY --from=compilers /opt/compilers /opt/compilers
COPY docs /app/docs
# The fetch stage cannot run a target-platform binary, so each checker the agent is handed proves
# it runs here, through the same launcher path the agent's tester will invoke.
RUN set -eu; \
    for name in reference dev; do /opt/compilers/"$name"/node_modules/.bin/tsc --version >/dev/null; done; \
    mkdir -p /app/tester && chown -R node:node /app/tester && node --version
WORKDIR /app
USER node
