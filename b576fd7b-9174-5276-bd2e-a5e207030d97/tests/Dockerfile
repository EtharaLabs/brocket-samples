# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Fetch stage: runs on the builder, resolves every graded build for the target platform.
#
# Each TypeScript 7 development build ships its Go executable as a per-platform optional
# dependency, so a stage running on the builder has to resolve the *target* platform's package
# rather than its own. TARGETOS and TARGETARCH carry that target; npm names an architecture the
# way Node does, where amd64 is x64. --ignore-scripts is what keeps this cross-safe: no
# postinstall runs on the builder, so nothing here needs to execute a target-platform binary.
FROM --platform=$BUILDPLATFORM node:26.13.0-bookworm-slim@sha256:add5c17c14752c54d2f3d519ec46a3815684d41c33f198bcb09fb998f7dcbf68 AS compilers
ARG TARGETOS
ARG TARGETARCH
# Security boundary: the eleven graded builds exist in this image alone, never in the agent image.
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) npm_cpu=x64 ;; \
      arm64) npm_cpu=arm64 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    install_one() { \
      npm install --prefix "$1" --ignore-scripts --no-audit --no-fund \
        --os "$TARGETOS" --cpu "$npm_cpu" "$2"; \
    }; \
    install_one /opt/compilers/reference typescript@6.0.3; \
    install_one /opt/compilers/dev typescript@7.1.0-dev.20261113.1; \
    for version in 7.1.0-dev.20260721.1 7.1.0-dev.20260722.1 7.1.0-dev.20260723.1 \
                   7.1.0-dev.20260818.1 7.1.0-dev.20260819.1 7.1.0-dev.20261013.1 \
                   7.1.0-dev.20261014.1 7.1.0-dev.20261027.1 7.1.0-dev.20261028.1 \
                   7.1.0-dev.20261103.1 7.1.0-dev.20261104.1; do \
      install_one "/opt/compilers/$version" "typescript@$version"; \
    done; \
    rm -rf /root/.npm

FROM node:26.13.0-bookworm-slim@sha256:add5c17c14752c54d2f3d519ec46a3815684d41c33f198bcb09fb998f7dcbf68
ENV GOMAXPROCS=2
COPY --from=compilers /opt/compilers /opt/compilers
# The fetch stage cannot run a target-platform binary, so every graded build proves it runs here,
# through the exact launcher path grade.mts and check.mts invoke. A missing or wrong-architecture
# optional dependency therefore fails the image build rather than scoring a submission zero.
RUN set -eu; \
    count=0; \
    for tsc in /opt/compilers/*/node_modules/.bin/tsc; do \
      "$tsc" --version >/dev/null; count=$((count + 1)); \
    done; \
    test "$count" -eq 13 || { echo "expected 13 checkers, proved $count" >&2; exit 1; }
COPY . /tests
RUN chmod 700 /tests && chmod +x /tests/test.sh && mkdir -p /app/tester /logs/verifier \
 && chown 65534:65534 /app/tester

WORKDIR /tests
# Root is deliberate: /tests stays 0700 against the submission, and the grader drops to uid 65534
# to launch it, which needs the privilege it drops.
USER root
