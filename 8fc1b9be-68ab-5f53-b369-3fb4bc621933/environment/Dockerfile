# syntax=docker/dockerfile:1
# Environment for the rustc MIR bounds-check elision task.
# Build-time network fetches the pinned source, the stage0 bootstrap and CI LLVM.
# The agent runs with no network, so every dependency is baked in here.
#
# Base note: Amazon Linux 2023 is used rather than Ubuntu because archive.ubuntu.com
# resolves to IPv6 only from the build host and the host has no IPv6 egress, so an
# apt-based layer crawls on fetches that never complete. The AL2023 repositories are
# AWS hosted and reachable over IPv4 from this instance.
#
# Multi-platform note: amazonlinux:2023 is a manifest list covering amd64 and arm64, every dnf
# package below is architecture-neutral, and download-ci-llvm resolves the host triple's CI
# artifact, so this file needs no per-architecture branch. Build the arm64 image on a native
# arm64 builder: the warm stage-1 build is the dominant cost and does not fit the declared
# build_timeout_sec under QEMU emulation.
FROM amazonlinux:2023

RUN dnf -y install \
      gcc gcc-c++ make cmake ninja-build python3 git \
      tar gzip xz file which openssl-devel pkgconfig glibc-devel \
    && dnf clean all

# task.toml declares agent.user = "1000:1000", because a solver never runs as root. The
# checkout and the whole warm build are therefore produced *as* that uid rather than chowned
# to it afterwards: a `chown -R` over this tree plus its build output would duplicate roughly
# eighteen gigabytes into a new layer, where building as the user costs nothing.
RUN groupadd -g 1000 agent \
    && useradd -u 1000 -g 1000 -m -s /bin/bash agent \
    && mkdir -p /app \
    && chown 1000:1000 /app

USER 1000:1000

ARG RUST_COMMIT=58cf8f9c35b355199727627d07ae34a4e2846d67
WORKDIR /app
RUN git init rust \
    && cd rust \
    && git remote add origin https://github.com/rust-lang/rust.git \
    && git fetch --depth 1 origin ${RUST_COMMIT} \
    && git checkout FETCH_HEAD

WORKDIR /app/rust
# download-ci-llvm avoids a 1-2 hour LLVM build.
# vendor is deliberately NOT set: bootstrap treats vendor = true as "a vendor directory
# must already exist" and refuses when it does not. The offline rebuild the agent needs
# is served instead by the cargo registry cache this image layer bakes in, together with
# CARGO_NET_OFFLINE below. The agent edits compiler source only, never a manifest, so
# Cargo.lock does not move and offline resolution succeeds from the cache.
RUN printf '%s\n' \
      '[llvm]' \
      'download-ci-llvm = true' \
      '[build]' \
      'extended = false' \
      'docs = false' \
      '[rust]' \
      'channel = "nightly"' \
      'incremental = true' \
      'debug-logging = false' \
      > bootstrap.toml

# Warm the build so the agent edit-rebuild loop is incremental rather than cold. Run as the
# agent uid, so every artifact it will later overwrite is already owned by it.
RUN python3 x.py build --stage 1 library

ENV CARGO_NET_OFFLINE=true
WORKDIR /app/rust

# Harness integration for the SForge runner on the brocket EC2 box, added to this run copy
# only and not to the draft. SForge installs the agent CLI with `sudo -E` and its submit tool
# reads JSON with jq, so the agent user gets both, the way the other brocket bundles grant it.
# AL2023's sudoers secure_path omits /usr/local/bin, where the Node tarball lands, so the
# agent's sudo path adds it back, matching the Debian default those bundles rely on.
USER root
RUN dnf -y install sudo jq \
    && dnf clean all \
    && printf '%s\n' \
         'Defaults:agent secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' \
         'agent ALL=(ALL) NOPASSWD:ALL' \
         > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && visudo -cf /etc/sudoers.d/agent
USER 1000:1000
