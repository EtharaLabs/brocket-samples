#!/bin/bash
# Verifier entry point. Runs in the separate judge image, which carries typescript@6.0.3 and the
# fourteen graded Go builds; the submission arrives as the agent's /app/tester tree.
#
# Fails closed: every exit path leaves a reward on disk and emits the structured block the
# declared parser reads, and any path that cannot establish a legitimate score leaves 0.
set -u
mkdir -p /logs/verifier

REWARD=/logs/verifier/reward.json

# Write the floor before any work, not after it. Harbor kills this container at
# verifier.timeout_sec from outside this script, so a fallback that only runs after the grader
# returns never runs at all on a timeout: the reward file is absent and the trial raises
# RewardFileNotFoundError instead of scoring 0. Harbor's own adapter review asks for exactly
# this ("test.sh always (re)writes the reward file on every code path ... never trusts a
# pre-existing reward file").
printf '{"reward": 0.0, "validity_gate": 0, "caught": 0}\n' > "$REWARD"
printf '0.0\n' > /logs/verifier/reward.txt
# The CTRF floor is written here too, not after the grader. Every early exit below leaves the
# script before any grading, and a path that produces no CTRF at all is not the same as one that
# honestly reports zero tests run. grade.py overwrites this with the real case list.
printf '{"results":{"tool":{"name":"brocket-tsdiff-grader"},"summary":{"tests":0,"passed":0,"failed":0,"pending":0,"skipped":0,"other":0},"tests":[]}}\n' \
  > /logs/verifier/ctrf.json

# Harbor scores from $REWARD, the sforge structured_json parser from this stdout block, and the
# two must agree. grade.py prints a plain summary and no markers, so this trap is the only
# emitter, and it covers every exit including the early ones below. Never `exec` the grader:
# that replaces this shell, the trap never runs, and every submission scores zero on a parse
# miss.
__sforge_emit() {
  local __score=0.0
  if [ -f "$REWARD" ]; then
    __score=$(python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print(float(d.get("reward", d.get("total", 0.0))))
except Exception:
    print(0.0)' "$REWARD" 2>/dev/null || echo 0.0)
  fi
  printf '>>>>> Start Structured Result\n{"score": %s}\n>>>>> End Structured Result\n' "$__score"
}
trap __sforge_emit EXIT

# Locate the submitted tester. Under the brocket launcher the collected tree lands back at its
# declared path, but Harbor's separate-verifier mode mirrors a collected artifact's absolute
# container path under the artifacts mount, so /app/tester also appears as
# /logs/artifacts/app/tester. Both are tried, then the tree is discovered anywhere under the
# mount, so a layout change in the harness degrades into a slower search rather than a zero
# that looks like a failed submission.
TESTER=""
for candidate in /app/tester/run /logs/artifacts/app/tester/run /logs/artifacts/tester/run \
                 /logs/artifacts/workspace/tester/run /workspace/tester/run; do
  [ -f "$candidate" ] && { TESTER="$candidate"; break; }
done
if [ -z "$TESTER" ] && [ -d /logs/artifacts ]; then
  FOUND=$(find /logs/artifacts -maxdepth 12 -type f -path '*/tester/run' -print 2>/dev/null | sort | head -1)
  [ -n "$FOUND" ] && TESTER="$FOUND"
fi

if [ -z "$TESTER" ]; then
  echo "verifier: no tester/run found at the declared entry point or under /logs/artifacts" >&2
  exit 0
fi
echo "verifier: grading the tester at $TESTER" >&2

# grade.py requires the executable bit, and artifact collection does not always preserve modes.
# A submission that is executable in the agent's sandbox must not score zero for a reason that
# is not about its behaviour.
chmod +x "$TESTER" 2>/dev/null || true

# The grader writes to a scratch path and is promoted only once it parses. Writing straight to
# reward.json would let a half-written file survive a mid-write death, and a truncated-but-
# non-empty file reads as VerifierOutputParseError rather than as the zero it should be.
# report.json, reward.txt and ctrf.json resolve from dirname(--out), which is unchanged.
graded=0
python3 /tests/grader/grade.py \
  --tester "$TESTER" \
  --budget 120 \
  --seed 20261113 \
  --jobs 4 \
  --out "$REWARD.part" && graded=1

if [ "$graded" -eq 1 ] \
   && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$REWARD.part" 2>/dev/null; then
  mv "$REWARD.part" "$REWARD"
else
  rm -f "$REWARD.part"
fi
