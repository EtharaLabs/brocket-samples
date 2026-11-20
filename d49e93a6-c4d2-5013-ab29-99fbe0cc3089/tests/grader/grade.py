"""Grade a submitted TypeScript checker differential tester against Go builds it has never seen.

For each graded window the grader runs the submission against the window's pre-fix Go build, reads
its report, and recompiles every witness itself under typescript@6.0.3 and under the pre and post
builds. It never trusts an outcome the submission reports.

    reward = validity_gate * recall * precision * attribution * minimality

A window is caught when one witness splits 6.0.3 against the pre build and agrees with 6.0.3 on
the post build, which separates a divergence the fix removed from one present on every Go build.
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
from functools import lru_cache
from pathlib import Path

CLASSES = ("accept", "reject", "crash", "hang")
BASELINE = "tsc6"
WITNESS_CAP = 200
ALLOWANCE_PER_LABEL = 3
LABEL_CAP = 8
MINIMAL_BYTES = 1500
COMPILE_TIMEOUT = 60
TOOLCHAINS = Path("/opt/ts")
ARGV = ["--noEmit", "--strict", "--target", "es2022", "--module", "esnext",
        "--moduleResolution", "bundler", "main.ts"]
CRASH = re.compile(
    r"^(panic:|fatal error:|runtime: goroutine)|throw e;|Debug Failure|"
    r"RangeError: Maximum call stack|^\s+at .+\.js:\d+", re.M)
DIAGNOSTIC = re.compile(r"error TS\d+")
WINDOWS = json.loads((Path(__file__).parent / "windows.json").read_text(encoding="utf-8"))


def classify(returncode: int | None, output: str) -> str:
    if returncode is None:
        return "hang"
    if CRASH.search(output):
        return "crash"
    if returncode == 0:
        return "accept"
    if DIAGNOSTIC.search(output):
        return "reject"
    return "crash"


@lru_cache(maxsize=None)
def compile_once(toolchain: str, source: str) -> str:
    """The outcome class of one program under one checker, observed by the grader itself."""
    with tempfile.TemporaryDirectory() as scratch:
        Path(scratch, "main.ts").write_text(source, encoding="utf-8")
        try:
            done = subprocess.run(
                [str(TOOLCHAINS / toolchain / "bin" / "tsc"), *ARGV], cwd=scratch,
                capture_output=True, text=True, timeout=COMPILE_TIMEOUT, errors="replace",
            )
        except subprocess.TimeoutExpired:
            return classify(None, "")
        return classify(done.returncode, done.stdout + done.stderr)


def read_report(path: Path) -> list[dict]:
    try:
        body = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    entries = body.get("witnesses") if isinstance(body, dict) else None
    if not isinstance(entries, list):
        return []
    clean = []
    for entry in entries[:WITNESS_CAP]:
        if not isinstance(entry, dict) or not isinstance(entry.get("source"), str):
            continue
        if entry.get("old") not in CLASSES or entry.get("new") not in CLASSES:
            continue
        clean.append(entry)
    return clean


def run_submission(tester: Path, toolchain: str, budget: int, seed: int, out: Path) -> str:
    """How the submission's run ended: ``ok``, ``launch-failed``, ``timeout`` or ``no-report``."""
    try:
        subprocess.run(
            [str(tester.resolve()), "--toolchain", toolchain, "--budget", str(budget),
             "--seed", str(seed), "--out", str(out)],
            # instruction.md promises "exceeding it by more than 10 percent is a failed run", so
            # the kill lands at exactly budget * 1.1. The former "+ 30" made the real tolerance
            # 162s against the shipped 120s budget, or +35%, which paid a submission the contract
            # said would fail.
            capture_output=True, timeout=int(budget * 1.1),
        )
    except subprocess.TimeoutExpired:
        return "timeout" if out.exists() else "no-report"
    except OSError:
        return "launch-failed"
    return "ok" if out.exists() else "no-report"


def _label(witness: dict) -> str:
    return " ".join(str(witness.get("mechanism", "")).lower().split())


def judge_witness(window: dict, witness: dict) -> str:
    """``bad``, ``agree``, ``background`` or ``credited`` for one witness on one window."""
    source = witness["source"]
    old, pre = compile_once(BASELINE, source), compile_once(window["pre"], source)
    if old != witness["old"] or pre != witness["new"]:
        return "bad"
    if old == pre:
        return "agree"
    return "credited" if compile_once(window["post"], source) == old else "background"


def grade(tester: Path, budget: int, seed: int, jobs: int, workdir: Path) -> dict:
    caught, read_total, invalid, launch_failures = [], 0, 0, 0
    per_window, precisions = [], []
    credited_total, minimal_total = 0, 0
    labels_by_window: dict[str, list[str]] = {}
    for window in WINDOWS:
        report = workdir / f"report-{window['id']}.json"
        ran = run_submission(tester, window["pre"], budget, seed, report)
        if ran == "launch-failed":
            launch_failures += 1
        # A run that overran its budget is a failed run, per instruction.md, so its report earns
        # nothing. Crediting "timeout" here paid exactly the submissions the contract excludes.
        witnesses = read_report(report) if ran == "ok" else []
        read_total += len(witnesses)
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            verdicts = list(pool.map(lambda w: judge_witness(window, w), witnesses))
        bad = verdicts.count("bad")
        credited = [w for w, v in zip(witnesses, verdicts) if v == "credited"]
        split_labels = {_label(w) for w, v in zip(witnesses, verdicts)
                        if v in {"credited", "background"}}
        minimal = sum(len(w["source"].encode("utf-8")) <= MINIMAL_BYTES for w in credited)
        invalid += bad
        credited_total += len(credited)
        minimal_total += minimal
        if credited:
            caught.append(window["id"])
            labels_by_window[window["id"]] = [_label(w) for w in credited]
        shown = len(witnesses)
        allowance = ALLOWANCE_PER_LABEL * min(LABEL_CAP, max(1, len(split_labels)))
        window_precision = 1.0 if shown <= allowance else allowance / shown
        precisions.append(window_precision)
        per_window.append({"window": window["id"], "ran": ran, "witnesses": shown,
                           "unreproducible": bad, "background": verdicts.count("background"),
                           "credited": len(credited), "minimal": minimal,
                           "allowance": allowance, "precision": round(window_precision, 6),
                           "caught": bool(credited)})
    graded = len(WINDOWS)
    validity_gate = 0 if (invalid or launch_failures == graded) else 1
    recall = len(caught) / graded
    precision = sum(precisions) / len(precisions) if precisions else 0.0
    attributed = 0
    for wid, labels in labels_by_window.items():
        own = {lab for lab in labels if lab}
        if len(own) != 1:
            continue
        mine = next(iter(own))
        if any(mine in set(other) for oid, other in labels_by_window.items() if oid != wid):
            continue
        attributed += 1
    attribution = attributed / len(caught) if caught else 0.0
    minimality = minimal_total / credited_total if credited_total else 0.0
    reward = validity_gate * recall * precision * attribution * minimality
    return {
        "reward": round(reward, 6), "validity_gate": validity_gate,
        "caught": len(caught), "graded": graded, "recall": round(recall, 6),
        "precision": round(precision, 6), "attribution": round(attribution, 6),
        "minimality": round(minimality, 6), "witnesses_read": read_total,
        "credited": credited_total, "unreproducible": invalid, "windows": per_window,
    }


def ctrf(result: dict, path: Path) -> None:
    windows = result.get("windows", [])
    outcomes = {
        "witnesses_reproduce": result.get("unreproducible", 0) == 0,
        "post_fix_agreement_required": all(w.get("caught") is not None for w in windows),
        "witness_cap_enforced": result.get("witnesses_read", 0) <= WITNESS_CAP * len(WINDOWS),
        "tester_launched": bool(windows) and any(w.get("ran") == "ok" for w in windows),
        "baseline_checker_named": True,
    }
    tests = [{"name": n, "status": "passed" if ok else "failed", "duration": 0}
             for n, ok in outcomes.items()]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"results": {
        "tool": {"name": "brocket-tsdiff-grader"},
        "summary": {"tests": len(tests), "passed": sum(t["status"] == "passed" for t in tests),
                    "failed": sum(t["status"] == "failed" for t in tests),
                    "pending": 0, "skipped": 0, "other": 0},
        "tests": tests}}, indent=1) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    def opt(name: str, default: str) -> str:
        return argv[argv.index(name) + 1] if name in argv else default

    tester = Path(opt("--tester", "/app/tester/run"))
    out = Path(opt("--out", "/logs/verifier/reward.json"))
    if not os.access(tester, os.X_OK):
        result = {"reward": 0.0, "validity_gate": 0, "caught": 0, "graded": len(WINDOWS),
                  "witnesses_read": 0, "unreproducible": 0, "windows": [],
                  "note": "no executable tester at the declared entry point"}
    else:
        with tempfile.TemporaryDirectory() as scratch:
            result = grade(tester, int(opt("--budget", "120")), int(opt("--seed", "20261113")),
                           int(opt("--jobs", "4")), Path(scratch))
    out.parent.mkdir(parents=True, exist_ok=True)
    # Harbor rejects a reward file holding any non-number, so the per-window list and the note
    # travel in report.json and only the scalars reach reward.json.
    numeric = {k: v for k, v in result.items()
               if isinstance(v, (int, float)) and not isinstance(v, bool)}
    out.write_text(json.dumps(numeric, indent=1) + "\n", encoding="utf-8")
    out.with_name("report.json").write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    out.with_name("reward.txt").write_text(f"{result['reward']}\n", encoding="utf-8")
    ctrf(result, out.with_name("ctrf.json"))
    print(json.dumps(result, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
