#!/bin/bash
set -eu

mkdir -p /app/tester
cp /solution/tester/generate.py /app/tester/generate.py
cp /solution/tester/run /app/tester/run
chmod +x /app/tester/run

/app/tester/run --toolchain dev --budget 60 --seed 0 --out /tmp/selfcheck.json >/dev/null
