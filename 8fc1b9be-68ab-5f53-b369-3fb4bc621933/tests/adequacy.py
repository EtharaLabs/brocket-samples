#!/usr/bin/env python3
"""Checker adequacy and statement-ambiguity checks (FORGE Phase build item 10a).

Each obligation is run here rather than asserted in the feasibility bundle, because a bundle
that never runs is inert and an inert required instrument caps the task rather than passing it.

sentinel   An easy case whose count is known by construction. The counter must report exactly
           that count. A counter that cannot get an easy case right grades nothing.
malformed  A case the counter cannot read. It must fail loudly rather than report zero. This is
           the load-bearing one: if an unreadable case counted as zero bounds checks, then a
           submission that merely broke the compiler would score as though it had proved every
           check redundant, and breaking the compiler is the easiest way to remove a check.
ambiguity  The objective resolves to exactly one graded outcome. The same compiler graded twice
           must yield the identical reward, so the statement admits one answer and not a range.

Usage: adequacy.py <rust_root> <rustc>
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

NO_INDEXING = """
pub fn f(a: u32, b: u32) -> u32 {
    a.wrapping_add(b)
}
"""

NOT_RUST = """
this file is not Rust and cannot be compiled {{{ ???
"""


def _counter():
    sys.path.insert(0, str(HERE))
    import count_bounds_checks as c  # noqa: PLC0415

    return c


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: adequacy.py <rust_root> <rustc>", file=sys.stderr)
        return 2
    rust_root, rustc = Path(argv[1]), argv[2]
    counter = _counter()
    expected = json.loads((HERE / "corpus" / "expected.json").read_text(encoding="utf-8"))

    results: list[tuple[str, str, bool, str]] = []

    def record(kind: str, name: str, ok: bool, detail: str) -> None:
        results.append((kind, name, ok, detail))

    work = Path(tempfile.mkdtemp(prefix="bce-adequacy-"))

    # sentinel: a function that indexes nothing carries no bounds check.
    plain = work / "no_indexing.rs"
    plain.write_text(NO_INDEXING, encoding="utf-8")
    try:
        bounds, _ = counter.count(rustc, plain)
        record("sentinel", "no_indexing counts 0", bounds == 0, "counted %r" % bounds)
    except Exception as exc:  # noqa: BLE001
        record("sentinel", "no_indexing counts 0", False, "raised %s" % type(exc).__name__)

    # sentinel: every must-keep case still carries exactly the count the baseline recorded,
    # which is what the soundness gate reads. A drifting counter would move that gate.
    for name, want in sorted(expected["must_keep"].items()):
        source = HERE / "corpus" / "must_keep" / name
        try:
            bounds, _ = counter.count(rustc, source)
            record("sentinel", "%s counts %d" % (name, want), bounds == want, "counted %r" % bounds)
        except Exception as exc:  # noqa: BLE001
            record(
                "sentinel",
                "%s counts %d" % (name, want),
                False,
                "raised %s" % type(exc).__name__,
            )

    # malformed: a source the compiler rejects must raise, never count as zero.
    broken = work / "not_rust.rs"
    broken.write_text(NOT_RUST, encoding="utf-8")
    try:
        bounds, _ = counter.count(rustc, broken)
        record("malformed", "uncompilable source raises", False, "returned %r" % bounds)
    except Exception as exc:  # noqa: BLE001
        record("malformed", "uncompilable source raises", True, "raised %s" % type(exc).__name__)

    # malformed: a compiler that is not there must raise, never count as zero.
    try:
        bounds, _ = counter.count(str(work / "no-such-rustc"), plain)
        record("malformed", "absent compiler raises", False, "returned %r" % bounds)
    except Exception as exc:  # noqa: BLE001
        record("malformed", "absent compiler raises", True, "raised %s" % type(exc).__name__)

    # malformed, at the grader: an unreadable must-keep case must zero the soundness gate rather
    # than read as a removed check. Proven by grading a corpus whose must-keep case cannot build.
    sys.path.insert(0, str(HERE))
    import grade as grader  # noqa: PLC0415

    sabotaged = dict(expected["must_keep"])
    sabotaged["not_rust.rs"] = 1
    probe = HERE / "corpus" / "must_keep" / "not_rust.rs"
    planted = False
    try:
        probe.write_text(NOT_RUST, encoding="utf-8")
        planted = True
        counts = grader.measure(rustc, "must_keep", sorted(sabotaged))
        unreadable = counts.get("not_rust.rs", "missing")
        record(
            "malformed",
            "grader reports an unreadable case as None",
            unreadable is None,
            "reported %r" % (unreadable,),
        )
    except OSError as exc:
        record("malformed", "grader reports an unreadable case as None", False, "setup failed: %s" % exc)
    finally:
        if planted:
            probe.unlink(missing_ok=True)

    # ambiguity: one compiler, two gradings, one outcome.
    first = grader.grade(rust_root, rustc)
    second = grader.grade(rust_root, rustc)
    same = first["reward"] == second["reward"] and first["counts"] == second["counts"]
    record(
        "ambiguity",
        "one compiler grades to one outcome",
        same,
        "rewards %r and %r" % (first["reward"], second["reward"]),
    )

    width = max(len(name) for _, name, _, _ in results)
    failures = 0
    for kind in ("sentinel", "malformed", "ambiguity"):
        print("== %s ==" % kind)
        for row_kind, name, ok, detail in results:
            if row_kind != kind:
                continue
            failures += 0 if ok else 1
            print("  %-*s  %s  %s" % (width, name, "ok  " if ok else "FAIL", detail))
        print()

    print("adequacy: %d checks, %d failed" % (len(results), failures))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
