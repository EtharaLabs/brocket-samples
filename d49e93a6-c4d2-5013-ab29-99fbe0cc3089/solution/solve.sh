#!/bin/bash
# Oracle: install the reference tester at the graded entry point and self-check it on dev.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p /app/tester
cp -R "$here/tester/." /app/tester/
chmod +x /app/tester/run
/app/tester/run --toolchain dev --budget 120 --seed 1 --out /tmp/self-check.json
cat /tmp/self-check.json
