#!/bin/bash
# Verifier entry point. Runs in the separate judge image, which carries the frozen reference
# checker and the eleven graded native builds; the submission arrives as the agent's /app/tester
# tree.
#
# Fails closed: every exit path leaves a reward on disk and exactly one structured block on
# stdout, and any path that cannot establish a legitimate score leaves 0.
set -u
mkdir -p /logs/verifier

REWARD=/logs/verifier/reward.json
GRADER_OUT=/logs/verifier/grader-stdout.log
: > "$GRADER_OUT"

# Write the floor before any work, not after it. Harbor kills this container at
# verifier.timeout_sec from outside this script, so a fallback that only runs after the grader
# returns never runs at all on a timeout: the reward file is absent and the trial raises
# RewardFileNotFoundError instead of scoring 0. Harbor's own adapter review asks for exactly
# this ("test.sh always (re)writes the reward file on every code path ... never trusts a
# pre-existing reward file").
printf '{"reward":0,"validity_gate":0}\n' > "$REWARD"
printf '0\n' > /logs/verifier/reward.txt
# The CTRF floor is written here too, not after the grader. Every early exit below leaves the
# script before any grading, and a path that produces no CTRF at all is not the same as one that
# honestly reports zero tests run. grade.mts overwrites this with the real check list.
printf '{"results":{"tool":{"name":"typescript-checker-differential"},"summary":{"tests":0,"passed":0,"failed":0,"pending":0,"skipped":0,"other":0},"tests":[]}}\n' \
  > /logs/verifier/ctrf.json

# grade.mts prints the structured block itself, with the full metrics payload. This trap is the
# fallback for every path that never reaches it: an unresolvable tester, a grader that died, a
# grader killed mid-run. It checks the captured stdout first so the parser never sees two blocks,
# which would make the score depend on which one it read. Never `exec` the grader: that replaces
# this shell and the trap never runs.
__sforge_emit() {
  grep -q '>>>>> Start Structured Result' "$GRADER_OUT" 2>/dev/null && return 0
  local __score=0.0
  if [ -f "$REWARD" ]; then
    __score=$(node -e 'try{const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(Number(d.reward ?? d.total ?? 0)))}catch(e){process.stdout.write("0")}' "$REWARD" 2>/dev/null || echo 0)
  fi
  echo '>>>>> Start Structured Result'
  printf '{"valid":false,"score":%s,"pass_rate":%s,"total_tests":0,"passed":0,"failed":0,"errors":1,"summary":"the grader did not complete, so no witness was recomputed and the validity gate is zero","details":[],"metrics":{"reward":%s,"validity_gate":0}}\n' \
    "$__score" "$__score" "$__score"
  echo '>>>>> End Structured Result'
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

# The grader requires the executable bit, and artifact collection does not always preserve
# modes. A submission that is executable in the agent's sandbox must not score zero for a reason
# that is not about its behaviour.
chmod +x "$TESTER" 2>/dev/null || true

# The grader writes to a scratch path and is promoted only once it parses. Writing straight to
# reward.json would let a half-written file survive a mid-write death, and a truncated-but-
# non-empty file reads as VerifierOutputParseError rather than as the zero it should be.
# report.json, reward.txt and ctrf.json resolve from dirname(--out), which is unchanged.
#
# stdout is captured rather than streamed so the trap can tell whether the structured block was
# printed, then replayed verbatim so the parser still reads it.
graded=0
node /tests/grader/grade.mts \
  --tester "$TESTER" \
  --budget 300 \
  --seed 20261113 \
  --out "$REWARD.part" > "$GRADER_OUT" 2>&1 && graded=1
cat "$GRADER_OUT"

if [ "$graded" -eq 1 ] \
   && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$REWARD.part" 2>/dev/null; then
  mv "$REWARD.part" "$REWARD"
else
  graded=0
  rm -f "$REWARD.part"
fi
