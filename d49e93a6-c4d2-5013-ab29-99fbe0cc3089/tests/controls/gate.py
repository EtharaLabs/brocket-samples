"""The qualification gate: does the naive baseline reach any graded window?

    python3 gate.py SECONDS [--jobs N] [--seed N] [--out FILE]

For each window in /tests/grader/windows.json it runs the naive baseline against the pre-fix build
for SECONDS, then recompiles every program it split on against the post-fix build. A program that
splits before the fix and agrees with typescript@6.0.3 after it reaches that window, and the
contract then excludes the window from the graded set. Run inside the judge image.
"""

from __future__ import annotations

import concurrent.futures
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, "/tests/grader")

import grade  # noqa: E402


def main(argv: list[str]) -> int:
    seconds = float(argv[1])
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 4
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 500
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("gate.json")
    record = []
    for window in grade.WINDOWS:
        with tempfile.TemporaryDirectory(prefix=f"gate-{window['id']}-") as scratch:
            done = subprocess.run(
                [sys.executable, "-B", str(Path(__file__).with_name("naive_baseline.py")), window["pre"],
                 str(seconds), "--jobs", str(jobs), "--seed", str(seed), "--out", scratch],
                check=True, capture_output=True, text=True, timeout=int(seconds) + 900)
            tried = json.loads(done.stdout.strip().splitlines()[-1])["tried"]
            splits = sorted(Path(scratch).glob("*.ts"))

            def verdict(path: Path) -> dict | None:
                text = path.read_text(encoding="utf-8")
                old = grade.compile_once(grade.BASELINE, text)
                pre, post = grade.compile_once(window["pre"], text), grade.compile_once(window["post"], text)
                if pre != old and post == old:
                    return {"program": text, "old": old, "pre": pre, "post": post}
                return None

            with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
                flips = [row for row in pool.map(verdict, splits) if row is not None]
        record.append({"window": window["id"], "pre": window["pre"], "post": window["post"],
                       "tried": tried, "sampled_splits": len(splits), "flips": len(flips),
                       "reached": bool(flips), "witnesses": flips[:3]})
        print(f"{window['id']}: {tried} tried, {len(splits)} splits, {len(flips)} flip -> "
              f"{'REACHED (exclude)' if flips else 'survives'}", flush=True)
        out.write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"windows": len(record),
                      "reached_by_naive": [r["window"] for r in record if r["reached"]],
                      "surviving": [r["window"] for r in record if not r["reached"]]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
