"""Does the reference tester catch each graded window, and stay quiet on the development build?

    python3 oracle_check.py TESTER [--budget N] [--seed N] [--out FILE]

It runs TESTER against every window's pre-fix build and against `dev`, then recompiles every
reported witness through the grader's own `judge_witness`. A window is caught when one witness is
credited: it splits typescript@6.0.3 from the pre build and agrees with it on the post build.
Run inside the judge image.
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, "/tests/grader")

import grade  # noqa: E402


def report(tester: Path, toolchain: str, budget: int, seed: int) -> tuple[str, list[dict]]:
    with tempfile.TemporaryDirectory() as scratch:
        out = Path(scratch) / "report.json"
        ran = grade.run_submission(tester, toolchain, budget, seed, out)
        return ran, grade.read_report(out)


def main(argv: list[str]) -> int:
    tester = Path(argv[1])
    budget = int(argv[argv.index("--budget") + 1]) if "--budget" in argv else 120
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 20261113
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("oracle.json")
    record = {"windows": []}
    for window in grade.WINDOWS:
        ran, witnesses = report(tester, window["pre"], budget, seed)
        verdicts = [(w, grade.judge_witness(window, w)) for w in witnesses]
        credited = [w["mechanism"] for w, v in verdicts if v == "credited"]
        record["windows"].append({
            "window": window["id"], "ran": ran, "witnesses": len(witnesses),
            "credited": credited, "bad": sum(v == "bad" for _, v in verdicts),
            "background": sum(v == "background" for _, v in verdicts), "caught": bool(credited)})
        print(f"{window['id']}: {len(witnesses)} shown, credited {credited}", flush=True)
    ran, dev = report(tester, "dev", budget, seed)
    record["development"] = {"ran": ran, "witnesses": len(dev),
                             "mechanisms": sorted({w.get("mechanism", "") for w in dev})}
    record["caught"] = sum(w["caught"] for w in record["windows"])
    out.write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"graded": len(grade.WINDOWS), "caught": record["caught"],
                      "development_witnesses": len(dev), "development_mechanisms": record["development"]["mechanisms"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
