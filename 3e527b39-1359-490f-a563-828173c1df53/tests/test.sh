#!/bin/bash
# Harbor verifier entry point. Fails closed: every exit path writes a reward, and any path that
# cannot establish a legitimate score writes 0.0 rather than leaving the reward absent.
#
# Order matters. The red lines are checked before the build, and the build before any grading, so
# a submission that wraps git or ships C never reaches the suite at all.
set -uo pipefail

REWARD=/logs/verifier/reward.json
PER_FAMILY=/logs/verifier/per_family.json
SUITE_LOGS=/logs/verifier/suite
# Harbor scores from $REWARD, the sforge parser from this stdout block. The trap covers every
# exit, zero() included. Never restore `exec` on the final grade.py call: it replaces this shell,
# the trap never runs, and every submission scores zero.
__sforge_emit() {
  local __total=0.0
  [ -f "$REWARD" ] && __total=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("reward",d.get("total",0.0)))' "$REWARD" 2>/dev/null || echo 0.0)
  printf '>>>>> Start Structured Result\n{"score": %s}\n>>>>> End Structured Result\n' "$__total"
}
trap __sforge_emit EXIT
MANIFEST=/tests/manifest.json
GRADER=/opt/grader
SOURCE="${SUITE_SOURCE:?SUITE_SOURCE is unset}"
ZIG="${ZIG:?ZIG is unset}"
WORK=/tmp/candidate

mkdir -p "$(dirname "$REWARD")" "$SUITE_LOGS"

zero() {
  echo "verifier: $1" >&2
  if [ -f "$MANIFEST" ]; then
    python3 "$GRADER/grade.py" --manifest "$MANIFEST" --candidate-bin /nonexistent \
      --source "$SOURCE" --reward "$REWARD" --per-family "$PER_FAMILY" --zero
  else
    # Numbers only: a "reason" string here raises VerifierOutputParseError instead of scoring 0.
    printf '{"reward": 0.0, "passed_weight": 0, "total_weight": 0}\n' > "$REWARD"
    printf '0.0\n' > "$(dirname "$REWARD")/reward.txt"
  fi
  exit 0
}

# The frozen manifest is the denominator. Without it there is nothing to measure against, and
# inventing one at grading time would let the measured set drift between rollouts.
[ -f "$MANIFEST" ] || zero "frozen case manifest absent at $MANIFEST"

# Locate the submitted source tree. Harbor mirrors a collected artifact's absolute container
# path under its artifacts directory, so the declared /home/workspace/zig-port normally lands at
# /logs/artifacts/home/workspace/zig-port. The known layouts are tried first, then the tree is
# discovered by its build.zig anywhere under the artifacts mount, so a layout change in the
# harness degrades into a slower search rather than a zero that looks like a failed submission.
SUBMISSION=""
for candidate in /logs/artifacts/home/workspace/zig-port /logs/artifacts/zig-port \
                 /logs/artifacts/workspace/zig-port /home/workspace/zig-port; do
  if [ -d "$candidate" ] && [ -f "$candidate/build.zig" ]; then SUBMISSION="$candidate"; break; fi
done
if [ -z "$SUBMISSION" ] && [ -d /logs/artifacts ]; then
  # Depth 12, not 6: the artifacts mount mirrors a collected path's absolute location, so a
  # harness that nests per-step or per-service directories pushes build.zig well past six levels.
  # A six-level cap was tested against /logs/artifacts/steps/main/collected/srv/agent/zig-port
  # and missed it by one, which is the failure this search exists to prevent.
  FOUND=$(find /logs/artifacts -maxdepth 12 -type f -name build.zig -print 2>/dev/null | sort | head -1)
  [ -n "$FOUND" ] && SUBMISSION=$(dirname "$FOUND")
fi
# Last resort: a directory by name even without build.zig, so a submission that deleted the
# scaffold's build file still reaches the rebuild step and fails there with a build log.
if [ -z "$SUBMISSION" ]; then
  for candidate in /logs/artifacts/home/workspace/zig-port /home/workspace/zig-port; do
    [ -d "$candidate" ] && { SUBMISSION="$candidate"; break; }
  done
fi
[ -n "$SUBMISSION" ] || zero "no submitted zig-port tree found among the collected artifacts"
echo "verifier: grading the tree at $SUBMISSION" >&2

rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$SUBMISSION/." "$WORK/" || zero "the submitted tree could not be copied"
# Any binary the agent shipped is discarded: the verifier grades what it rebuilds from source.
rm -rf "$WORK/zig-out" "$WORK/.zig-cache" "$WORK/zig-cache"
# cp -a preserved the agent's modes. The build runs as candidate and the suite as grader, so a
# tree shipped mode 0700 would be untraversable by one of them and score 0.0 for a reason that
# is not about the code. Readable and traversable for both, writable by neither's owner change.
chmod -R a+rX "$WORK" 2>/dev/null || true

# Red line: no C, C++, assembly or Rust sources, and no prebuilt objects, archives or binaries.
FORBIDDEN=$(find "$WORK" -type f \( \
    -name '*.c' -o -name '*.h' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.hpp' \
    -o -name '*.s' -o -name '*.S' -o -name '*.asm' -o -name '*.rs' \
    -o -name '*.o' -o -name '*.a' -o -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \
  \) -print | head -20)
[ -z "$FORBIDDEN" ] || zero "red line: submission carries non-Zig sources or prebuilt objects: $(echo "$FORBIDDEN" | tr '\n' ' ')"

# Red line: no embedded executable image smuggled inside any shipped file.
while IFS= read -r suspect; do
  [ -n "$suspect" ] || continue
  if grep -qal $'\x7fELF' "$suspect" 2>/dev/null; then
    zero "red line: submission carries an embedded executable image in $suspect"
  fi
done < <(find "$WORK" -type f -size +256c -print 2>/dev/null | head -2000)

# Rebuild from source as the unprivileged candidate user, which cannot read the reference binary.
chown -R candidate:candidate "$WORK" 2>/dev/null || true
BUILD_LOG="$SUITE_LOGS/build.log"
if ! setpriv --reuid=1001 --regid=1001 --clear-groups \
      env PATH=/usr/bin:/bin HOME=/tmp ZIG="$ZIG" \
      "$ZIG" build --build-file "$WORK/build.zig" --prefix "$WORK/zig-out" \
      > "$BUILD_LOG" 2>&1; then
  zero "submission did not rebuild under the pinned toolchain; see $BUILD_LOG"
fi
[ -x "$WORK/zig-out/bin/git" ] || zero "rebuild produced no zig-out/bin/git"

# The suite resolves GIT_EXEC_PATH by calling the candidate's own `git --exec-path`, so a binary
# that cannot answer it grades nothing. Checked here to separate that failure from a suite abort.
if ! setpriv --reuid=1001 --regid=1001 --clear-groups \
      env PATH=/usr/bin:/bin HOME=/tmp "$WORK/zig-out/bin/git" --exec-path > "$SUITE_LOGS/exec-path.txt" 2>&1; then
  echo "verifier: candidate could not answer --exec-path; every script will abort" >&2
fi

setpriv --reuid=2000 --regid=2000 --clear-groups \
  env PATH=/usr/bin:/bin HOME=/tmp PYTHONDONTWRITEBYTECODE=1 \
  python3 "$GRADER/grade.py" \
    --manifest "$MANIFEST" \
    --candidate-bin "$WORK/zig-out/bin" \
    --source "$SOURCE" \
    --reward "$REWARD" \
    --per-family "$PER_FAMILY" \
    --script-timeout 300
