# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# Agent sandbox. The solver reads the C source of git v2.56.1 and writes Zig. No runnable git
# reaches this image, by measurement: an executable reference lets a solver diff its output against
# an oracle command by command instead of implementing from the source, which scored 0.726 at three
# hours where source-reading probes scored 0.19. The C source stays; the binary does not.

ARG UBUNTU_DIGEST=sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852
ARG GIT_VERSION=2.56.1
ARG GIT_TARBALL_SHA256=f0b0bf89264b9bd2e1c640363e7529643989da76281600473c50745cd34a607f
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256_AMD64=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
ARG ZIG_SHA256_ARM64=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795
ARG GIT_MAKE_FLAGS="NO_TCLTK=1 NO_GETTEXT=1 NO_CURL=1 NO_OPENSSL=1 NO_PERL=1 NO_PYTHON=1"

# Stage 1: fetch and checksum every download on the build platform. Nothing is compiled here, so
# the stage stays cross-safe and selects the Zig build by $TARGETARCH.
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

# Stage 2: build the reference git for the target platform. Native build, so buildx emulates the
# non-native architecture rather than this stage carrying a cross toolchain.
FROM ubuntu:24.04@${UBUNTU_DIGEST} AS buildgit
ARG GIT_MAKE_FLAGS
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes build-essential make zlib1g-dev cargo rustc \
 && rm -rf /var/lib/apt/lists/*
COPY --from=fetch /src/git /src/git
WORKDIR /src/git
RUN set -euo pipefail; make -j"$(nproc)" prefix=/opt/git ${GIT_MAKE_FLAGS} install

# Stage 2b: prove the shipped scaffold compiles under the pinned toolchain. The image build fails
# if it does not, so a solver never meets a scaffold that cannot build. Nothing from this stage is
# copied forward, so no build output reaches the sandbox.
FROM ubuntu:24.04@${UBUNTU_DIGEST} AS scaffoldcheck
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
COPY --from=fetch /opt/zig /opt/zig
COPY scaffold/ /check/
WORKDIR /check
RUN set -euo pipefail; /opt/zig/zig build; test -x zig-out/bin/git

# Stage 3: the shipped sandbox. It carries the Zig toolchain the solver runs and zlib to link
# against. No C or Rust toolchain, no package cache, no runnable git, and no build residue reaches
# this layer. Every t/ tree is removed, contrib suites included, because the grader is that suite.
FROM ubuntu:24.04@${UBUNTU_DIGEST} AS runtime
ARG GIT_VERSION
LABEL org.opencontainers.image.title="3e527b39-1359-490f-a563-828173c1df53 agent sandbox"
LABEL org.opencontainers.image.description="Reimplement git v2.56.1 in Zig as a drop-in replacement."
LABEL org.opencontainers.image.licenses="GPL-2.0-only"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes zlib1g zlib1g-dev less \
 && rm -rf /var/lib/apt/lists/*
COPY --from=scaffoldcheck /check/build.zig /tmp/scaffold-verified.zig
RUN rm -f /tmp/scaffold-verified.zig
COPY --from=fetch /opt/zig /opt/zig
COPY --from=fetch /src/git /home/workspace/git-src
RUN set -euo pipefail; \
    rm -rf /home/workspace/git-src/t; \
    find /home/workspace/git-src -type d -name t -prune -exec rm -rf {} +; \
    userdel --remove ubuntu 2>/dev/null || true; \
    useradd --uid 1000 --user-group --create-home --shell /bin/bash solver; \
    mkdir -p /home/workspace/zig-port; \
    chown -R 1000:1000 /home/workspace
COPY --chown=1000:1000 scaffold/ /home/workspace/zig-port/
ENV PATH="/opt/zig:${PATH}"
WORKDIR /home/workspace/zig-port

# For the [extensions.sforge] path only; Harbor needs none of this. SForge's in-container
# installer shells out to `sudo -E bash -c ...` and fetches Node with curl, its submit helper
# parses with jq, and it writes the agent's settings to a hardcoded /home/agent/... while this
# bundle's solver is uid 1000 with home /home/solver. No git is added back: the solver still
# has no runnable reference, which is the whole point of this sandbox.
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
 && apt-get install --no-install-recommends --yes sudo jq curl ca-certificates xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && printf 'solver ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/solver \
 && chmod 0440 /etc/sudoers.d/solver \
 && visudo -cf /etc/sudoers.d/solver \
 && ln -s /home/solver /home/agent
USER 1000:1000
