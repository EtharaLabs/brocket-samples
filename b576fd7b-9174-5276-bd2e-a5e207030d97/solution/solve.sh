#!/bin/bash
# FORGE-CANARY-BEGIN
# FORGE-CANARY-SLOT-1: 3ddccc53ce11e5863c8da9b31e5ecf88a88aa81c5837517c50653000cf9c4deb
# FORGE-CANARY-SLOT-2: 9fd86250d3b787176068cbad3642f5444dbb5a1ae12fab88129041a8fbecc900
# FORGE-CANARY-SLOT-3: 0806122145c059db2a8c1cf847aed5b7954cafc1ea5184bed48b2294293eb661
# FORGE-CANARY-END
set -eu
mkdir -p /app/tester
cp /solution/tester/* /app/tester/
chmod +x /app/tester/run
/app/tester/run --toolchain dev --budget 300 --seed 0 --out /tmp/checker-selfcheck.json
node -e 'const r=JSON.parse(require("fs").readFileSync("/tmp/checker-selfcheck.json","utf8")); if(r.witnesses.length!==0)process.exit(1)'
