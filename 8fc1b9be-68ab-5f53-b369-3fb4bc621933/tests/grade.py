#!/usr/bin/env python3
"""Grade a submission compiler for the rustc MIR bounds-check elision task.

reward = generalization * soundness_gate * regression_gate

generalization counts checks rather than files, and weights them by mechanism class. Each class
contributes its declared mass in corpus/expected.json: the fraction removed within a class is scaled
by that mass and the scaled fractions are summed. Removing every check still scores exactly 1.0, so
the weighting changes the partial-credit gradient and never the ceiling. The classes are `arith`,
whose proof needs only reasoning inside the function body, and `callee`, whose proof needs a
postcondition of an opaque call that no intraprocedural domain can recover. soundness_gate is 0 the moment the
submission removes one check from a case whose check is reachable. regression_gate is 0 if MIR
validation or an observable-behaviour probe fails. So a no-op scores 0 on generalization, and removing
everything scores 0 on soundness.

Baseline counts come from corpus/expected.json, generated at authoring time from the unmodified
upstream compiler at the pinned commit. The grader never trusts a count the submission supplied.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REWARD = Path("/logs/verifier/reward.json")


def _counter():
    sys.path.insert(0, str(HERE))
    import count_bounds_checks as c  # noqa: PLC0415

    return c


def load_expected() -> dict:
    return json.loads((HERE / "corpus" / "expected.json").read_text(encoding="utf-8"))


def measure(rustc: str, group: str, names: list[str]) -> dict[str, int | None]:
    """bounds-assert count per case, or None when the case did not compile."""
    counter = _counter()
    out: dict[str, int | None] = {}
    for name in names:
        source = HERE / "corpus" / group / name
        try:
            bounds, _ = counter.count(rustc, source)
            out[name] = bounds
        except Exception:
            out[name] = None
    return out


OK_PROGRAM = """
fn main() {
    let v: Vec<u32> = (0..10).collect();
    let mut total = 0u32;
    for i in 0..v.len() {
        total += v[i];
    }
    for i in (0..v.len()).rev() {
        total += v[i];
    }
    let n = v.len();
    if n >= 2 {
        for i in 0..n - 1 {
            total += v[i + 1];
        }
    }
    println!("{}", total);
}
"""

PANIC_PROGRAM = """
fn main() {
    let v: Vec<u32> = (0..4).collect();
    // Opaque to the optimizer, and out of range: this check has to survive and fire.
    let i = std::env::args().count() + 9;
    println!("{}", v[i]);
}
"""


def _run(cmd: list[str], timeout: int = 600) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def regression(_rust_root: Path, rustc: str) -> tuple[bool, str]:
    """MIR validation over the whole corpus, plus observable behaviour, as a gate.

    The upstream mir-opt suite is deliberately not run. Its harness, compiletest, is not
    vendored in the environment image, and the verifier has no network, so the suite fails to
    build regardless of what was submitted; gating on it would zero every submission including
    a correct one. It would also be the wrong instrument: a new pass legitimately changes the
    MIR those tests record, so a correct submission would have to re-bless them.

    What the gate is actually for is that the compiler was not broken to make the corpus pass,
    and that is tested directly. Every case must still produce valid MIR. A program built from
    the shapes this pass rewrites must still compute the right answer, which catches a rewrite
    that corrupts control flow. And a genuinely out-of-range access must still panic, which
    catches a submission that simply stopped checking.
    """
    for group in ("must_keep", "should_remove"):
        # AppleDouble sidecars (`._name.rs`) are not Rust: any macOS copy of the corpus creates
        # them, rustc then fails on one, and the gate would zero an otherwise perfect submission.
        sources = sorted(
            p for p in (HERE / "corpus" / group).glob("*.rs")
            if not p.name.startswith("._")
        )
        for source in sources:
            validate = [
                rustc, "--crate-type=lib", "-O", "-Zvalidate-mir",
                "--emit=metadata", "-o", "/dev/null", str(source),
            ]
            try:
                done = _run(validate)
            except subprocess.TimeoutExpired:
                return False, "validate-mir timed out on %s" % source.name
            if done.returncode != 0:
                return False, "validate-mir failed on %s: %s" % (
                    source.name, (done.stderr or "").strip()[:200])

    work = Path(tempfile.mkdtemp(prefix="bce-regression-"))
    try:
        for name, body, expect_panic, expect_out in (
            ("ok_program", OK_PROGRAM, False, "135"),
            ("panic_program", PANIC_PROGRAM, True, None),
        ):
            source = work / ("%s.rs" % name)
            binary = work / name
            source.write_text(body, encoding="utf-8")
            try:
                built = _run([rustc, "-O", "-o", str(binary), str(source)])
            except subprocess.TimeoutExpired:
                return False, "%s timed out building" % name
            if built.returncode != 0:
                return False, "%s did not build: %s" % (
                    name, (built.stderr or "").strip()[:200])

            try:
                ran = _run([str(binary)], timeout=120)
            except subprocess.TimeoutExpired:
                return False, "%s timed out running" % name

            if expect_panic:
                if ran.returncode == 0:
                    return False, "an out-of-range access did not panic"
                if "index out of bounds" not in (ran.stderr or ""):
                    return False, "out-of-range access failed without a bounds-check panic: %s" % (
                        (ran.stderr or "").strip()[:200])
            else:
                if ran.returncode != 0:
                    return False, "%s exited %d: %s" % (
                        name, ran.returncode, (ran.stderr or "").strip()[:200])
                if (ran.stdout or "").strip() != expect_out:
                    return False, "%s printed %r, expected %r" % (
                        name, (ran.stdout or "").strip(), expect_out)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    return True, "ok"


def grade(rust_root: Path, rustc: str) -> dict:
    expected = load_expected()
    keep_names = sorted(expected["must_keep"])
    safe_names = sorted(expected["should_remove"])

    keep = measure(rustc, "must_keep", keep_names)
    unsound = [
        n for n in keep_names if keep[n] is not None and keep[n] < expected["must_keep"][n]
    ]
    build_failed = [n for n, v in keep.items() if v is None]
    soundness = 0.0 if unsound or build_failed else 1.0

    reg_ok, reg_note = regression(rust_root, rustc)
    regression_gate = 1.0 if reg_ok else 0.0

    safe = measure(rustc, "should_remove", safe_names)
    classes = expected["mechanism_class"]
    mass = expected["class_mass"]
    removable = sum(expected["should_remove"][n] for n in safe_names)
    removed = sum(
        max(0, expected["should_remove"][n] - safe[n])
        for n in safe_names
        if safe[n] is not None
    )
    per_class: dict[str, list[int]] = {k: [0, 0] for k in mass}
    for n in safe_names:
        slot = per_class[classes[n]]
        base = expected["should_remove"][n]
        slot[1] += base
        if safe[n] is not None:
            slot[0] += max(0, base - safe[n])
    generalization = sum(
        mass[k] * (got / total) for k, (got, total) in per_class.items() if total
    )

    reward = generalization * soundness * regression_gate
    return {
        "reward": round(reward, 6),
        "generalization": round(generalization, 6),
        "checks_removed": removed,
        "checks_removable": removable,
        "per_class": {k: {"removed": v[0], "removable": v[1]} for k, v in per_class.items()},
        "class_mass": mass,
        "soundness_gate": soundness,
        "regression_gate": regression_gate,
        "regression_note": reg_note,
        "unsound_removals": unsound,
        "did_not_compile": build_failed,
        "counts": {"must_keep": keep, "should_remove": safe},
    }


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: grade.py <rust_root> <rustc>", file=sys.stderr)
        return 2
    result = grade(Path(argv[1]), argv[2])
    REWARD.parent.mkdir(parents=True, exist_ok=True)
    # Harbor rejects a reward file holding any non-number, so the dicts, lists and notes in
    # `result` travel in report.json and only the scalars reach reward.json.
    numeric = {k: v for k, v in result.items()
               if isinstance(v, (int, float)) and not isinstance(v, bool)}
    REWARD.write_text(json.dumps(numeric, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    REWARD.with_name("report.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    REWARD.with_name("reward.txt").write_text(f"{result['reward']}\n", encoding="utf-8")
    summary = {
        k: result[k]
        for k in ("reward", "generalization", "checks_removed", "checks_removable",
                  "soundness_gate", "regression_gate")
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
