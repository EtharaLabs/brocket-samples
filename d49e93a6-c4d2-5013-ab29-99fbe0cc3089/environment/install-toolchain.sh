#!/bin/sh
# install-toolchain.sh <name> <npm spec> <entry under node_modules>
# Installs one checker build under /opt/ts/<name> and exposes it as /opt/ts/<name>/bin/tsc.
#
# Each Go-native build ships its executable as a per-platform optional dependency, so a fetch
# stage running on the builder must resolve the target platform's package rather than its own.
# TARGETOS and TARGETARCH carry that target; npm names an architecture the way Node does, where
# amd64 is x64. With neither set the install resolves for the running platform. The launcher is
# written but never run here, because a target-platform binary does not execute on the builder;
# the runtime stage proves every launcher it ships runs.
set -eu
name=$1; spec=$2; entry=$3

npm_os="${TARGETOS:-}"
case "${TARGETARCH:-}" in
  amd64) npm_cpu="x64" ;;
  *)     npm_cpu="${TARGETARCH:-}" ;;
esac

set -- install --prefix "/opt/ts/$name" --no-audit --no-fund --no-save --loglevel=error
if [ -n "$npm_os" ]; then set -- "$@" --os "$npm_os"; fi
if [ -n "$npm_cpu" ]; then set -- "$@" --cpu "$npm_cpu"; fi

mkdir -p "/opt/ts/$name/bin"
npm "$@" "$spec"
printf '#!/bin/sh\nexec /opt/node22/bin/node /opt/ts/%s/node_modules/%s "$@"\n' "$name" "$entry" > "/opt/ts/$name/bin/tsc"
chmod 755 "/opt/ts/$name/bin/tsc"
