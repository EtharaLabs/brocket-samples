#!/usr/bin/env python3
"""Count BoundsCheck assert terminators in the optimized MIR of one source file.

The score is structural, not behavioural: an out-of-bounds read need not crash, so
counting the asserts rustc actually emits is the only honest way to tell whether a
pass removed a check. The count is taken from the optimized MIR dump, after the
pass pipeline has run, so a removal is attributed to the optimizer and not to an
edit in the corpus source.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

# rustc renders the bounds-check assert with this message form in a MIR dump.
BOUNDS_ASSERT = re.compile(r"assert\(move _\d+, \"index out of bounds")
ANY_ASSERT = re.compile(r"^\s*assert\(", re.M)


def optimized_mir(rustc: str, source: Path, out_dir: Path) -> str:
    """The optimized MIR of ``source``, or raise CalledProcessError."""
    subprocess.run(
        [
            rustc,
            "--crate-type=lib",
            "-O",
            "-Zmir-opt-level=2",
            "--emit=mir",
            "-o",
            str(out_dir / "out.mir"),
            str(source),
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=300,
    )
    return (out_dir / "out.mir").read_text(encoding="utf-8", errors="replace")


def count(rustc: str, source: Path) -> tuple[int, int]:
    """(bounds_check_asserts, all_asserts) in the optimized MIR of ``source``."""
    with tempfile.TemporaryDirectory() as tmp:
        text = optimized_mir(rustc, source, Path(tmp))
    return len(BOUNDS_ASSERT.findall(text)), len(ANY_ASSERT.findall(text))


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: count_bounds_checks.py <rustc> <source.rs> [more.rs ...]", file=sys.stderr)
        return 2
    rustc, sources = argv[1], [Path(p) for p in argv[2:]]
    status = 0
    for source in sources:
        try:
            bounds, every = count(rustc, source)
        except subprocess.CalledProcessError as exc:
            print("%s BUILD-FAILED %s" % (source.name, (exc.stderr or "").strip()[:160]))
            status = 1
            continue
        except subprocess.TimeoutExpired:
            print("%s TIMEOUT" % source.name)
            status = 1
            continue
        print("%s bounds_asserts=%d all_asserts=%d" % (source.name, bounds, every))
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
