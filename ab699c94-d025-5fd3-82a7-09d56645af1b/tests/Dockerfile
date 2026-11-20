FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin

ARG DEBIAN_SNAPSHOT=20261104T212339Z
RUN printf '%s\n' \
      'Types: deb' \
      "URIs: http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}" \
      'Suites: trixie trixie-updates' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp' \
      '' \
      'Types: deb' \
      "URIs: http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}" \
      'Suites: trixie-security' \
      'Components: main' \
      'Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp' \
      > /etc/apt/sources.list.d/debian.sources \
 && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99snapshot \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates=20250419+deb13u1 \
      curl=8.14.1-2+deb13u7 \
      python3=3.13.5-1 \
 && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --default-toolchain none

RUN for tc in nightly-2026-07-27 nightly-2026-07-28 nightly-2026-08-14 ; do \
      rustup toolchain install "$tc" --profile minimal --no-self-update || exit 1 ; \
    done && rm -rf /opt/rustup/downloads /opt/rustup/tmp

RUN for tc in nightly-2026-08-15 nightly-2026-08-16 nightly-2026-09-10 ; do \
      rustup toolchain install "$tc" --profile minimal --no-self-update || exit 1 ; \
    done && rm -rf /opt/rustup/downloads /opt/rustup/tmp

RUN for tc in nightly-2026-09-11 nightly-2026-09-22 nightly-2026-09-24 ; do \
      rustup toolchain install "$tc" --profile minimal --no-self-update || exit 1 ; \
    done && rm -rf /opt/rustup/downloads /opt/rustup/tmp

RUN for tc in nightly-2026-09-30 nightly-2026-10-02 nightly-2026-10-05 nightly-2026-10-07 ; do \
      rustup toolchain install "$tc" --profile minimal --no-self-update || exit 1 ; \
    done && rm -rf /opt/rustup/downloads /opt/rustup/tmp \
 && rustup toolchain list

COPY . /tests
# /tests holds the answer key. grader/windows.json carries the seven pre/post nightly pins, the
# mechanism labels and the fix PR numbers, and the submitted tester runs inside this image, so a
# readable /tests means a graded process can read what it is being graded against. The agent
# cannot see this at development time; its program can at grading time, which is where it counts.
# Root-owned and 0700 is one half of the fix; grade.py dropping the tester to uid 65534 is the
# other. Mirrors b576fd7b/tests/Dockerfile, which already does this.
RUN chmod 0700 /tests/test.sh \
 && chown -R root:root /tests \
 && chmod -R go-rwx /tests \
 && mkdir -p /logs/verifier \
 && chown -R root:root /logs/verifier \
 && chmod 0755 /logs/verifier

WORKDIR /tests

# Deliberate, and the reason rule 11 is satisfied rather than bypassed: the grader needs root to
# keep /tests unreadable and to drop the submission to another uid. Nothing the agent wrote runs
# as root -- run_submission() in grader/grade.py launches it as 65534:65534 with no groups.
USER root
