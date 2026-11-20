# syntax=docker/dockerfile:1
# Judge image for the rustc MIR bounds-check elision task.
#
# The build context is this tests/ directory, which is what the launcher passes
# (harness/scripts/run_trajectory.sh builds the judge with ctx="$STAGE/tests"). So every COPY
# below is relative to tests/, and the reference solution is out of scope by construction:
# the launcher stages the bundle with solution/ excluded before it builds either image.
#
# This judge is heavy on purpose. The graded property is a property of a compiler, not of a
# script, so grading has to apply the agent's submitted compiler sources over a real checkout
# and rebuild. That is why the same pinned commit and the same warm stage-1 build as the work
# image are baked in here: the incremental rebuild was measured at about 42 seconds, while a
# cold build would not fit a submission inside the verifier timeout.
#
# Base note: Amazon Linux 2023, matching the work image. The stage-1 rustc built from the
# agent's tree has to execute in this container, so the libc has to match. The same IPv6
# reachability problem that rules out an apt base for the work image rules it out here.
#
# Multi-platform note: the architecture has to match the work image too, for the same reason the
# libc does. Build both images for the same platform on a native builder of that platform; the
# stage-1 paths this image's grader reads are derived from the host triple, not hardcoded.
FROM amazonlinux:2023

RUN dnf -y install \
      gcc gcc-c++ make cmake ninja-build python3 git \
      tar gzip xz file which openssl-devel pkgconfig glibc-devel \
    && dnf clean all

ARG RUST_COMMIT=58cf8f9c35b355199727627d07ae34a4e2846d67
WORKDIR /app
RUN git init rust \
    && cd rust \
    && git remote add origin https://github.com/rust-lang/rust.git \
    && git fetch --depth 1 origin ${RUST_COMMIT} \
    && git checkout FETCH_HEAD

WORKDIR /app/rust
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

RUN python3 x.py build --stage 1 library

ENV CARGO_NET_OFFLINE=true

# The grader and the graded corpus. These never reach the agent: this image is instantiated
# only by the harness, one container per submission, and destroyed after.
COPY . /opt/verifier/

# Harbor runs /tests/test.sh and test.sh resolves its helpers from dirname($0), so the whole
# tree has to land there too; tests/ is not uploaded when this Dockerfile exists.
COPY . /tests
RUN chmod 0755 /tests/test.sh

# The entry point the eval command drives. It writes the reward artifact task.toml declares,
# /logs/verifier/reward.json, and exits non-zero only when no compiler was built at all.
#
# One integration note for whoever writes the sforge task JSON: the structured_json parser
# reads a JSON block between the markers ">>>>> Start Structured Result" and
# ">>>>> End Structured Result". This grader prints a plain summary instead, so eval_cmd has
# to wrap it and emit those markers, the way the touchstone task definitions wrap their own
# scorers. Driving test.sh directly would score every submission zero on a parse miss.
WORKDIR /app/rust
