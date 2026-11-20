#!/bin/sh
# Harbor verifier entry point.
#
# This runs in its own container, built from tests/Dockerfile, because task.toml declares
# verifier.environment_mode = "separate". The agent's submitted compiler sources are overlaid
# on this container's own pristine checkout, and the compiler is rebuilt here.
#
# The rebuild is the point, not a convenience. Grading a binary the agent left behind would let
# the agent choose the artifact under test: it could build from sources it then reverted, or
# leave a compiler that never corresponded to what it submitted. Rebuilding from the submitted
# sources is what makes the score a property of the submission.
#
# Writes the reward artifact task.toml declares, /logs/verifier/reward.json.
#
# Two kinds of zero, kept apart on purpose
# ----------------------------------------
# A measured zero says the submission is worth nothing. An infrastructure zero says this box
# could not carry out the measurement. They were indistinguishable before: a measured oracle run
# on an under-provisioned box returned generalization 0.0 with soundness_gate and
# regression_gate both 1.0 -- the signature of grading a compiler that never received the
# submission, because tests/Dockerfile bakes a warm stage-1 build and the rebuild here silently
# did not consume the overlay. A reviewer could not tell that from a wrong answer.
#
# So this script now proves three things before it grades, and reports an infrastructure failure
# rather than a score when any of them does not hold:
#   1. the box meets the envelope task.toml declares,
#   2. the rebuild either consumed the submission or the submission changed nothing,
#   3. a stage-1 compiler exists to grade.
#
# Both paths still leave a reward file, so the trial never errors for want of one (fail closed).
# The infrastructure path additionally exits non-zero and writes verifier_status.json, which is
# what separates "not measurable here" from "measured, worth zero".
set -eu

RUST_DIR=${RUST_DIR:-/app/rust}
# Harbor mounts trial_dir/verifier at /logs/verifier; the override exists so the classification
# branches below can be exercised off-container, and is never set in a graded run.
LOGS=${VERIFIER_LOGS:-/logs/verifier}
STATUS="$LOGS/verifier_status.json"
BUILD_LOG="$LOGS/stage1-rebuild.log"

# Declared in task.toml under [verifier.environment]: cpus = 8, memory_mb = 16384,
# storage_mb = 61440. The thresholds below sit under those figures rather than at them, because
# a cgroup reports slightly less than it was granted and the image already occupies part of the
# volume. They exist to catch the measured failure (7000 MB / 20 GB) and not to quibble.
MIN_MEM_MB=15000
MIN_FREE_MB=20480
WANT_CPUS=8

# Fail closed before anything can exit non-zero under `set -eu`: a submission that does not
# compile has to score 0, not leave the reward absent and raise a trial error.
mkdir -p "$LOGS"
printf '0.0\n' > "$LOGS/reward.txt"
printf '{"reward": 0.0}\n' > "$LOGS/reward.json"
# Pessimistic from the first line. Harbor kills this container at [verifier].timeout_sec, and a
# kill during the rebuild leaves the floor above with no record of how it got there. Any status
# other than "graded" means the 0.0 on disk was never a measurement.
printf '{"status": "started", "reason": "verifier entered; nothing measured yet"}\n' > "$STATUS"

# reward.json may hold numbers only -- Harbor rejects any non-number in it, which is why the
# reason text goes to verifier_status.json and only flags travel in the reward.
infra() {
    printf '{"reward": 0.0, "graded": 0, "infra_failure": 1}\n' > "$LOGS/reward.json"
    printf '0.0\n' > "$LOGS/reward.txt"
    printf '{"status": "infra_failure", "reason": "%s"}\n' "$1" > "$STATUS"
    echo "verifier: INFRASTRUCTURE FAILURE: $1" >&2
    echo "verifier: this 0.0 is not a measurement of the submission; do not report it as one" >&2
    exit 1
}

# A real measurement that happens to be zero. Exits 0: the trial succeeded.
measured_zero() {
    printf '{"reward": 0.0, "graded": 1, "%s": 1}\n' "${2:-broke_a_declared_rule}" > "$LOGS/reward.json"
    printf '0.0\n' > "$LOGS/reward.txt"
    printf '{"status": "graded", "reason": "%s"}\n' "$1" > "$STATUS"
    echo "verifier: $1 -> reward 0.0" >&2
    exit 0
}

# ---------------------------------------------------------------------------
# 1. Does this box meet the declared envelope?
# ---------------------------------------------------------------------------
mem_limit_mb() {
    # cgroup v2, then v1, then the host view. "max" means unlimited, so fall through.
    if [ -r /sys/fs/cgroup/memory.max ]; then
        v=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
        [ "$v" != "max" ] && { echo $((v / 1024 / 1024)); return; }
    fi
    if [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        v=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
        # v1 reports a sentinel near 2^63 when unlimited.
        if [ "$v" -gt 0 ] 2>/dev/null && [ "$v" -lt 4000000000000 ] 2>/dev/null; then
            echo $((v / 1024 / 1024)); return
        fi
    fi
    awk '/^MemTotal:/ {printf "%d\n", $2 / 1024}' /proc/meminfo 2>/dev/null || echo 0
}

MEM_MB=$(mem_limit_mb 2>/dev/null || echo 0)
FREE_MB=$(df -Pk "$RUST_DIR" 2>/dev/null | awk 'NR==2 {printf "%d\n", $4 / 1024}' || echo 0)
CPUS=$(nproc 2>/dev/null || echo 0)

# `[ "" -gt 0 ]` is a usage error rather than a false, so an undetectable figure must read as 0.
case "$MEM_MB" in ''|*[!0-9]*) MEM_MB=0 ;; esac
case "$FREE_MB" in ''|*[!0-9]*) FREE_MB=0 ;; esac
case "$CPUS" in ''|*[!0-9]*) CPUS=0 ;; esac

echo "verifier: envelope: cpus=$CPUS memory=${MEM_MB}MB free=${FREE_MB}MB on $(uname -m)" >&2

# Memory and storage are gates: the measured failure was caused by both being short, and a
# stage-1 rustc rebuild cannot be made to fit under them.
if [ "$MEM_MB" -gt 0 ] && [ "$MEM_MB" -lt "$MIN_MEM_MB" ]; then
    infra "box provides ${MEM_MB}MB of memory, below the ${MIN_MEM_MB}MB this task needs (task.toml declares 16384MB); a stage-1 rustc rebuild cannot be measured here"
fi
if [ "$FREE_MB" -gt 0 ] && [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
    infra "only ${FREE_MB}MB free on $RUST_DIR, below the ${MIN_FREE_MB}MB this task needs (task.toml declares 61440MB); the rebuild will not complete"
fi
# CPU count only changes how long the rebuild takes, so it warns rather than gates.
if [ "$CPUS" -gt 0 ] && [ "$CPUS" -lt "$WANT_CPUS" ]; then
    echo "verifier: WARNING: $CPUS cpus against a declared $WANT_CPUS; the rebuild will be slower than the measured 42s and may approach [verifier].timeout_sec" >&2
fi

# bootstrap names its build directory after the host triple, so the stage-1 path is
# architecture-dependent and cannot be a constant on a multi-platform image.
case "$(uname -m)" in
    x86_64)        HOST_TRIPLE=x86_64-unknown-linux-gnu ;;
    aarch64|arm64) HOST_TRIPLE=aarch64-unknown-linux-gnu ;;
    *) infra "unsupported machine for stage-1 rustc: $(uname -m)" ;;
esac

RUSTC=${RUSTC:-"$RUST_DIR/build/$HOST_TRIPLE/stage1/bin/rustc"}
TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

cd "$RUST_DIR"

# ---------------------------------------------------------------------------
# 2. What did the submission actually change, and what are we about to replace?
# ---------------------------------------------------------------------------
# The image checks out the pinned commit with git, so the pristine state is recorded in .git and
# the overlay is visible as a working-tree change. --porcelain is used rather than `git diff`
# because a new pass arrives as an untracked file, which `git diff` does not report.
# Not piped. `$?` after a pipeline is the last command's status, so piping git into head would
# report head's success and hide a missing repository -- the one condition this must not miss.
set +e
git -C "$RUST_DIR" status --porcelain -- compiler/ \
    > "$LOGS/submission-delta.txt" 2> "$LOGS/git-status.err"
GIT_RC=$?
set -e
SUBMISSION_DELTA=$(head -20 "$LOGS/submission-delta.txt" 2>/dev/null || true)
if [ "$GIT_RC" -ne 0 ]; then
    # The pinned baseline in .git is the only record of what the submission changed. Without it
    # an empty delta cannot be told from an unread one, and the declared red lines below cannot
    # be checked at all -- so this is a refusal to measure, not a zero.
    infra "git could not read the pinned baseline in $RUST_DIR (exit $GIT_RC); neither the declared red lines nor rebuild provenance can be checked"
fi
if [ -n "$SUBMISSION_DELTA" ]; then
    echo "verifier: submission changes under compiler/:" >&2
    echo "$SUBMISSION_DELTA" | sed 's/^/verifier:   /' >&2
else
    echo "verifier: submission leaves compiler/ byte-identical to the pinned commit" >&2
fi

# ---------------------------------------------------------------------------
# 2b. The red lines instruction.md declares, which nothing used to check.
# ---------------------------------------------------------------------------
# `instruction.md:32-37` forbids two things and both live inside the submitted compiler/ tree,
# so the submission could do either and still be paid. Breaking a stated rule is the
# submission's own doing, so each of these is a measured zero rather than an infrastructure
# failure. `Cargo.lock cannot move` needs no check here: it sits outside compiler/ and
# extensions.sforge.submit_paths collects compiler/ only, so it is structurally unreachable.
red_line_paths() {
    git -C "$RUST_DIR" status --porcelain -- "$1" 2>/dev/null | grep -vE '^\?\?' | head -20 || true
}

MIR_BUILD_TOUCHED=$(red_line_paths 'compiler/rustc_mir_build/')
if [ -n "$MIR_BUILD_TOUCHED" ]; then
    echo "$MIR_BUILD_TOUCHED" | sed 's/^/verifier:   /' >&2
    measured_zero "the submission changes compiler/rustc_mir_build/, which instruction.md forbids: the task asks the optimizer to eliminate a redundant assertion, not the lowering to stop emitting it"
fi

# A modified or deleted test file is the detectable form of "weakened". Untracked additions are
# excluded above, so a submission may add tests freely.
TESTS_TOUCHED=$(red_line_paths 'compiler/' | grep -E '(^|/)tests?(\.rs)?(/|$)|_test\.rs$' || true)
if [ -n "$TESTS_TOUCHED" ]; then
    echo "$TESTS_TOUCHED" | sed 's/^/verifier:   /' >&2
    measured_zero "the submission modifies or deletes upstream test files under compiler/, which instruction.md forbids"
fi

# File-level status misses a test deleted from inside a surviving file, so the attribute totals
# are compared against the pinned commit as well. Only a decrease is a violation: adding tests is
# allowed. git grep reads tracked files only, which is what makes the comparison like-for-like.
attr_total() {
    git -C "$RUST_DIR" grep -c -F "$2" $1 -- compiler/ 2>/dev/null \
        | awk -F: '{s += $NF} END {print s + 0}'
}
for ATTR in '#[test]' '#[cfg(test)]'; do
    BEFORE=$(attr_total HEAD "$ATTR")
    AFTER=$(attr_total '' "$ATTR")
    case "$BEFORE" in ''|*[!0-9]*) BEFORE=0 ;; esac
    case "$AFTER" in ''|*[!0-9]*) AFTER=0 ;; esac
    echo "verifier: $ATTR under compiler/: $BEFORE at the pinned commit, $AFTER as submitted" >&2
    if [ "$AFTER" -lt "$BEFORE" ]; then
        measured_zero "the submission removes $((BEFORE - AFTER)) occurrence(s) of $ATTR under compiler/, which instruction.md forbids"
    fi
done

fingerprint() {
    if [ -e "$1" ] && command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | cut -d' ' -f1
    elif [ -e "$1" ]; then
        # No sha256sum: size plus mtime still detects a binary that was never rewritten.
        stat -c '%s-%Y' "$1" 2>/dev/null || echo unknown
    else
        echo absent
    fi
}
RUSTC_BEFORE=$(fingerprint "$RUSTC")

# ---------------------------------------------------------------------------
# 3. Rebuild, and classify a failure rather than letting it read as a zero.
# ---------------------------------------------------------------------------
# The rebuild runs inside [verifier].timeout_sec, so left unbounded it can consume the whole
# budget and let Harbor's kill land mid-grade. The judge image bakes a warm stage-1 build
# (tests/Dockerfile:50) and the incremental rebuild was measured at about 42 s, so this budget is
# two orders of magnitude of headroom and still leaves the larger half of 7200 s for grading --
# a pass measured at 27 m 45 s on the reference box. Exceeding it means the rebuild was not
# incremental, which is a statement about this box and not about the submission.
REBUILD_BUDGET=${REBUILD_BUDGET:-3000}
set +e
if command -v timeout > /dev/null 2>&1; then
    timeout "$REBUILD_BUDGET" python3 x.py build --stage 1 library > "$BUILD_LOG" 2>&1
else
    python3 x.py build --stage 1 library > "$BUILD_LOG" 2>&1
fi
BUILD_RC=$?
set -e

if [ "$BUILD_RC" -eq 124 ]; then
    tail -40 "$BUILD_LOG" >&2 || true
    infra "the stage-1 rebuild exceeded its ${REBUILD_BUDGET}s budget, so it was not the incremental rebuild this image is built for; grading was not attempted"
fi

if [ "$BUILD_RC" -ne 0 ]; then
    echo "verifier: stage-1 rebuild exited $BUILD_RC; last 40 lines of $BUILD_LOG:" >&2
    tail -40 "$BUILD_LOG" >&2 || true

    # Resource death and signal death are this box failing, not the submission being wrong.
    if grep -qE 'No space left on device|Cannot allocate memory|out of memory|OOM|Killed|signal: 9|signal: 15|SIGKILL' "$BUILD_LOG"; then
        infra "the stage-1 rebuild was killed by the box (out of memory, disk or time), exit $BUILD_RC; see stage1-rebuild.log"
    fi
    # A compile error in the submitted sources is the submission's own fault and scores zero.
    if grep -qE '^error(\[E[0-9]{4}\])?:|error: could not compile|error: aborting due to' "$BUILD_LOG"; then
        measured_zero "the submitted compiler sources do not build" did_not_build
    fi
    # Anything else is unclassified, and an unclassified failure must not be paid as a score.
    infra "the stage-1 rebuild failed with exit $BUILD_RC and no compile error in the log, so the cause is not attributable to the submission; see stage1-rebuild.log"
fi

if [ ! -x "$RUSTC" ]; then
    infra "no stage-1 rustc at $RUSTC after rebuilding the submitted tree"
fi

RUSTC_AFTER=$(fingerprint "$RUSTC")

# The load-bearing check. tests/Dockerfile:50 bakes a warm stage-1 build into this image, so a
# rebuild that silently did nothing leaves a working compiler on disk -- the pristine one. If the
# submission changed compiler/ and the binary is byte-identical afterwards, the thing about to be
# graded is not the thing that was submitted, and every number downstream is meaningless.
if [ "$RUSTC_BEFORE" = "$RUSTC_AFTER" ]; then
    if [ -n "$SUBMISSION_DELTA" ]; then
        infra "the submission modified compiler/ but $RUSTC is byte-identical after the rebuild ($RUSTC_BEFORE): the rebuild did not consume the submission, so the compiler on disk is this image's pristine build"
    elif [ "$GIT_USABLE" -ne 1 ]; then
        infra "$RUSTC is byte-identical after the rebuild and the pinned baseline could not be read, so an empty submission cannot be told from a rebuild that did nothing"
    else
        # An empty submission legitimately reproduces the pristine binary. The declared null
        # floor is what it should be paid, so grade it and let it score its zero honestly.
        echo "verifier: no submission delta; grading the pristine compiler against the declared null floor" >&2
    fi
fi

echo "verifier: stage-1 rustc fingerprint ${RUSTC_BEFORE} -> ${RUSTC_AFTER}" >&2

# Not exec'd. A grader that dies mid-run would leave the floor 0.0 on disk with a "graded"
# status beside it -- the same indistinguishable zero this script exists to prevent -- so the
# status stays pessimistic until grade.py is known to have finished.
printf '{"status": "grading_incomplete", "reason": "grade.py was launched and has not reported"}\n' > "$STATUS"
set +e
python3 "$TESTS_DIR/grade.py" "$RUST_DIR" "$RUSTC"
GRADE_RC=$?
set -e
if [ "$GRADE_RC" -ne 0 ]; then
    infra "grade.py exited $GRADE_RC without completing a grading pass, so the reward on disk is the floor and not a measurement"
fi
printf '{"status": "graded", "reason": "stage-1 rebuild consumed the submission and grade.py completed"}\n' > "$STATUS"
