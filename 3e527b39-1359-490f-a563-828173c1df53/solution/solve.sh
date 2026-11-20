#!/bin/sh
# Oracle entry point. Harbor's OracleAgent copies this bundle's solution/ tree to /solution
# inside the agent environment and runs this script, so placing the reference sources into the
# agent workspace is all that is required: the verifier discards any binary and rebuilds from
# whatever Zig source the workspace holds.
set -eu

WORKSPACE=/home/workspace/zig-port

test -d /solution || { echo "solve.sh: /solution is not mounted" >&2; exit 1; }
test -d "$WORKSPACE" || { echo "solve.sh: $WORKSPACE is missing" >&2; exit 1; }

cp -f /solution/build.zig "$WORKSPACE/build.zig"
rm -rf "$WORKSPACE/src"
cp -a /solution/src "$WORKSPACE/src"

# Prove the placed tree builds here rather than leaving that to the verifier, so an oracle run
# that cannot compile fails loudly at the agent step instead of scoring zero at the grading step.
cd "$WORKSPACE"
"${ZIG:-/opt/zig/zig}" build
test -x "$WORKSPACE/zig-out/bin/git"
