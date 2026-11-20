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
      git=1:2.47.3-0+deb13u1 \
 && rm -rf /var/lib/apt/lists/*

ARG DEV_NIGHTLY=nightly-2026-11-08
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${DEV_NIGHTLY}" \
 && ln -s "$(rustup toolchain list | head -n1 | cut -d' ' -f1)" /opt/rustup/toolchains/dev 2>/dev/null || true \
 && rustup toolchain link dev "$(rustup which rustc | sed 's#/bin/rustc##')" \
 && rustc +dev -vV

# Absolute path on purpose: useradd lives in /usr/sbin, and the PATH this image declares above
# deliberately omits /usr/sbin, so the bare name exits 127 and the image cannot build. Adding
# /usr/sbin to that PATH instead would change the environment the agent runs in, which is not a
# build fix.
RUN /usr/sbin/useradd --create-home --uid 1000 --user-group --shell /bin/bash agent \
 && mkdir -p /app \
 && chown -R agent:agent /app /opt/rustup /opt/cargo

COPY --chown=agent:agent docs /app/docs

WORKDIR /app
USER agent
