# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# Separate verifier image. It carries the grader, so no registry ever holds these bytes: the
# manifest declares no docker_image for [verifier.environment] and Harbor builds this locally.
#
# GIT_MAKE_FLAGS is byte-identical to environment/Dockerfile on purpose. The agent compares its
# work against the system git in its own sandbox, so if the grader's reference were configured
# differently the agent would be tuning to a target that is not the one scoring it.
#
# Access is split by user rather than by image:
#   /opt/suite      the t/ tree, test-tool and templates, readable by the grader user. Running
#                   the suite needs these, and none of them is a `git` binary.
#   /opt/reference  the reference git binary, mode 0700 and root-owned. It is used only by the
#                   frozen selection runs, never while a candidate is being graded, so no
#                   candidate process can reach a real git even transitively.

ARG UBUNTU_DIGEST=sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
ARG GIT_VERSION=2.56.1
ARG GIT_TARBALL_SHA256=f0b0bf89264b9bd2e1c640363e7529643989da76281600473c50745cd34a607f
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256_AMD64=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
ARG ZIG_SHA256_ARM64=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795
ARG GIT_MAKE_FLAGS="NO_TCLTK=1 NO_GETTEXT=1 NO_CURL=1 NO_OPENSSL=1 NO_PERL=1 NO_PYTHON=1"

# Stage 1: fetch and checksum on the build platform. Cross-safe, nothing compiled.
FROM --platform=$BUILDPLATFORM ubuntu:24.04@${UBUNTU_DIGEST} AS fetch
ARG TARGETOS
ARG TARGETARCH
ARG GIT_VERSION
ARG GIT_TARBALL_SHA256
ARG ZIG_VERSION
ARG ZIG_SHA256_AMD64
ARG ZIG_SHA256_ARM64
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /dl
RUN set -euo pipefail; \
    curl -fsSL -o git.tar.xz "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz"; \
    echo "${GIT_TARBALL_SHA256}  git.tar.xz" | sha256sum -c -; \
    mkdir -p /src/git && tar -xJf git.tar.xz -C /src/git --strip-components=1
RUN set -euo pipefail; \
    case "${TARGETARCH}" in \
      amd64) zig_arch=x86_64; zig_sha="${ZIG_SHA256_AMD64}" ;; \
      arm64) zig_arch=aarch64; zig_sha="${ZIG_SHA256_ARM64}" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-${TARGETOS}-${ZIG_VERSION}.tar.xz"; \
    echo "${zig_sha}  zig.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/zig && tar -xJf zig.tar.xz -C /opt/zig --strip-components=1

# Stage 2: build the reference git, its test helpers and its templates for the target platform.
# The feasibility probe established that t/test-lib.sh refuses to run without t/helper/test-tool
# and without a built template directory, so this build is what makes the suite runnable at all.
# cargo is present because the upstream build adopts Rust where it finds it, which is the
# configuration the probe measured.
FROM ubuntu:24.04@${UBUNTU_DIGEST} AS buildref
ARG GIT_MAKE_FLAGS
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes build-essential make zlib1g-dev cargo rustc \
 && rm -rf /var/lib/apt/lists/*
# Built at its final runtime path on purpose. make writes absolute build-machine paths into
# GIT-BUILD-OPTIONS (GIT_TEST_TEMPLATE_DIR, GIT_TEST_GITPERLLIB, GIT_SOURCE_DIR), test-lib.sh
# sources that file, and a stale path there makes every script BAIL_OUT before any test runs.
COPY --from=fetch /src/git /opt/suite/git
WORKDIR /opt/suite/git
RUN set -euo pipefail; \
    make -j"$(nproc)" prefix=/opt/reference ${GIT_MAKE_FLAGS} install; \
    make -j"$(nproc)" ${GIT_MAKE_FLAGS} t/helper/test-tool; \
    make -j"$(nproc)" ${GIT_MAKE_FLAGS} GIT-BUILD-OPTIONS; \
    test -x t/helper/test-tool; \
    test -d templates/blt; \
    grep -q "GIT_TEST_TEMPLATE_DIR='/opt/suite/git/templates/blt'" GIT-BUILD-OPTIONS

# Stage 3: the grader. It carries python3 for the harness and the pinned Zig to rebuild a
# candidate from source, and no package cache or build residue.
FROM ubuntu:24.04@${UBUNTU_DIGEST} AS runtime
LABEL org.opencontainers.image.title="3e527b39-1359-490f-a563-828173c1df53 verifier"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes python3 zlib1g zlib1g-dev file util-linux \
 && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /opt/zig /opt/zig
COPY --from=buildref /opt/reference /opt/reference
COPY --from=buildref /opt/suite/git /opt/suite/git
COPY --from=buildref /opt/suite/git/t/helper/test-tool /opt/suite/git/t/helper/test-tool
COPY --from=buildref /opt/suite/git/templates/blt /opt/suite/git/templates/blt
COPY --from=buildref /opt/suite/git/GIT-BUILD-OPTIONS /opt/suite/git/GIT-BUILD-OPTIONS

# The candidate rebuild runs as `candidate` (1001) and the graded suite runs as `grader` (2000).
# Neither can reach the reference binary: /opt/reference/bin is 0700 root:root, so the group
# split only governs the suite tree, and no graded process reaches a real git transitively.
RUN set -euo pipefail; \
    groupadd --gid 2000 grader; \
    useradd --uid 2000 --gid 2000 --create-home --shell /bin/bash grader; \
    useradd --uid 1001 --user-group --create-home --shell /bin/bash candidate; \
    chown -R root:grader /opt/suite; \
    chmod -R o-rwx /opt/suite; \
    chown -R root:root /opt/reference; \
    chmod 0700 /opt/reference/bin; \
    mkdir -p /logs/verifier /opt/grader; \
    chown -R grader:grader /logs/verifier

COPY grader/ /opt/grader/
COPY test.sh /tests/test.sh
# Harbor skips the tests/ upload whenever tests/Dockerfile exists, so this image must
# self-provide the frozen manifest test.sh reads, or the grader zeroes every submission.
COPY manifest.json /tests/manifest.json
# For the [extensions.sforge] path only: its cwd is /home/workspace, and SForge runs the eval as
# `cd <cwd> && ...` inside this image, so the directory has to exist here too. Harbor supplies
# its own working directory and never reads this one.
RUN mkdir -p /home/workspace
RUN chmod 0755 /tests/test.sh \
 && chmod 0644 /tests/manifest.json

ENV PYTHONDONTWRITEBYTECODE=1
ENV SUITE_SOURCE=/opt/suite/git
ENV REFERENCE_BIN=/opt/reference/bin
ENV ZIG=/opt/zig/zig
WORKDIR /tests
