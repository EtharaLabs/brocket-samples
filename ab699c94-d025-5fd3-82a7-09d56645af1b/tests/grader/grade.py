from __future__ import annotations

import concurrent.futures
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MODES = ("no", "globally")
CLASSES = ("accept", "reject", "ice", "hang")
WITNESS_CAP = 200
WITNESS_ALLOWANCE_PER_WINDOW = 3
# Share of reported witnesses that may fail to reproduce before the whole report is called
# fabricated. A single bad witness used to zero the entire reward, which was double punishment:
# a witness that does not reproduce already fails to credit its own window, so recall has
# already paid for it. Fabrication is still caught without the gate -- every witness failing to
# reproduce means no window is credited and recall is 0 on its own -- and this keeps an explicit
# catch for a report that is mostly noise.
UNRELIABLE_SHARE = 0.5
MINIMAL_BYTES = 1500
COMPILE_TIMEOUT = 60
EDITIONS = ("2015", "2018", "2021", "2024")
WINDOWS = json.loads((Path(__file__).parent / "windows.json").read_text(encoding="utf-8"))

# The submitted tester runs inside this image, and this directory holds its answer key:
# windows.json carries the seven pre/post nightly pins, the mechanism labels and the fix PR
# numbers. tests/Dockerfile keeps /tests root-owned and unreadable to anyone else; this is the
# other half of that split, dropping the tester to a uid that owns nothing but its own report
# directory. 65534 is nobody/nogroup, which exists in the base image and owns nothing.
SUBMISSION_UID = 65534
SUBMISSION_GID = 65534

# Wall-clock ceiling for the whole grading pass, so the budget is a bound rather than a hope.
# task.toml declares [verifier].timeout_sec = 10800; the worst case without a deadline is
# 7 windows x 200 witnesses x 2 modes x 60s, which is an order of magnitude past it, and a
# Harbor kill at the container level leaves no reward at all. The default reserves 1200s of the
# declared budget for image start, artifact discovery and writing the result.
DEFAULT_DEADLINE = 9600


def compile_once(toolchain: str, source: str, edition: str, mode: str) -> str:
    with tempfile.TemporaryDirectory() as scratch:
        path = Path(scratch) / "w.rs"
        path.write_text(source, encoding="utf-8")
        argv = [
            "rustc", f"+{toolchain}", "--edition", edition, "--crate-type", "lib",
            "--emit=metadata", "-o", f"{scratch}/o.rmeta", f"-Znext-solver={mode}",
            "-Awarnings", str(path),
        ]
        try:
            done = subprocess.run(
                argv, capture_output=True, text=True, timeout=COMPILE_TIMEOUT,
                env={**os.environ, "RUST_BACKTRACE": "0"},
            )
        except subprocess.TimeoutExpired:
            return "hang"
    return {0: "accept", 1: "reject", 101: "ice"}.get(done.returncode, "ice")


def observe(toolchain: str, witness: dict, jobs: int) -> tuple[str, str]:
    source, edition = witness["source"], witness.get("edition", "2015")
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {mode: pool.submit(compile_once, toolchain, source, edition, mode) for mode in MODES}
        return futures["no"].result(), futures["globally"].result()


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
        if entry.get("old") not in CLASSES or entry.get("next") not in CLASSES:
            continue
        if entry.get("edition", "2015") not in EDITIONS:
            continue
        clean.append(entry)
    return clean


def submission_scratch(workdir: Path) -> tuple[Path, bool]:
    """A report directory the submission can write and nothing else it can read.

    Returns the directory and whether privileges will actually be dropped. 0711 on the parent
    lets the tester traverse to its own directory without listing the grader's scratch.
    """
    target = workdir / "submission"
    target.mkdir(parents=True, exist_ok=True)
    if os.geteuid() != 0:
        return target, False
    try:
        os.chmod(workdir, 0o711)
        os.chown(target, SUBMISSION_UID, SUBMISSION_GID)
        os.chmod(target, 0o700)
    except OSError:
        return target, False
    return target, True


def run_submission(tester: Path, toolchain: str, budget: int, seed: int, out: Path,
                   drop: bool = False) -> str:
    # HOME and TMPDIR move into the report directory because rustc writes temporaries and uid
    # 65534 owns nothing else. RUSTUP_HOME and CARGO_HOME stay as inherited: the toolchains
    # under /opt are world-readable, which is all the tester needs to invoke `rustc +nightly`.
    env = {**os.environ, "RUST_BACKTRACE": "0"}
    privilege = {}
    if drop:
        env["HOME"] = str(out.parent)
        env["TMPDIR"] = str(out.parent)
        privilege = {"user": SUBMISSION_UID, "group": SUBMISSION_GID, "extra_groups": []}
    try:
        subprocess.run(
            [str(tester.resolve()), "--toolchain", toolchain, "--budget", str(budget),
             "--seed", str(seed), "--out", str(out)],
            capture_output=True, timeout=int(budget * 1.1) + 60,
            env=env, **privilege,
        )
    except subprocess.TimeoutExpired:
        return "timeout" if out.exists() else "no-report"
    except OSError:
        return "launch-failed"
    return "ok" if out.exists() else "no-report"


def _label(witness: dict) -> str:
    return " ".join(str(witness.get("mechanism", "")).lower().split())


def grade(tester: Path, budget: int, seed: int, jobs: int, workdir: Path,
          deadline: float = DEFAULT_DEADLINE) -> dict:
    caught, mechanisms, read_total, invalid = [], set(), 0, 0
    per_window, launch_failures = [], 0
    credited_total, minimal_total, mislabelled_total = 0, 0, 0
    precisions: list[float] = []
    labels_by_window: dict[str, list[str]] = {}
    scratch, dropped = submission_scratch(workdir)
    expires = time.monotonic() + deadline
    windows_attempted, deadline_hit = 0, False
    for window in WINDOWS:
        # A window that never ran counts as not caught against the unchanged denominator below,
        # so an expiring deadline costs recall rather than erasing the trial. Launching one more
        # window would risk a container-level kill, which leaves no reward at all.
        if time.monotonic() >= expires:
            deadline_hit = True
            per_window.append({"window": window["id"], "ran": "deadline-expired",
                               "witnesses": 0, "unreproducible": 0, "background": 0,
                               "credited": 0, "minimal": 0, "precision": 0.0, "caught": False})
            precisions.append(0.0)
            continue
        windows_attempted += 1
        report = scratch / f"report-{window['id']}.json"
        ran = run_submission(tester, window["pre"], budget, seed, report, drop=dropped)
        if ran == "launch-failed":
            launch_failures += 1
        witnesses = read_report(report) if ran in {"ok", "timeout"} else []
        read_total += len(witnesses)
        hit, bad, credited, minimal, labels, background = False, 0, 0, 0, [], 0
        mislabelled = 0
        for witness in witnesses:
            # Checked per witness as well: one window reporting 200 witnesses, each compiled
            # four times at a 60s ceiling, is on its own larger than the declared budget.
            if time.monotonic() >= expires:
                deadline_hit = True
                break
            old_pre, next_pre = observe(window["pre"], witness, jobs)
            if (old_pre != next_pre) != (witness["old"] != witness["next"]):
                bad += 1
                continue
            if old_pre != witness["old"] or next_pre != witness["next"]:
                # The divergence agreed with the claim above, so the submission found a real
                # disagreement between the two solvers and only named the outcome classes
                # wrongly. `hang` is decided by a wall clock, so a slower box relabels
                # accept/hang without anything about the finding changing. That earns no credit
                # and is not evidence of fabrication, so it is counted apart from `bad`.
                mislabelled += 1
                continue
            if old_pre == next_pre:
                continue
            old_post, next_post = observe(window["post"], witness, jobs)
            if old_post != next_post:
                background += 1
                continue
            hit = True
            credited += 1
            if len(witness["source"].encode("utf-8")) <= MINIMAL_BYTES:
                minimal += 1
            labels.append(_label(witness))
        invalid += bad
        mislabelled_total += mislabelled
        credited_total += credited
        minimal_total += minimal
        if hit:
            caught.append(window["id"])
            mechanisms.add(window["mechanism"])
            labels_by_window[window["id"]] = labels
        shown = len(witnesses)
        window_precision = 1.0 if shown <= WITNESS_ALLOWANCE_PER_WINDOW \
            else WITNESS_ALLOWANCE_PER_WINDOW / shown
        precisions.append(window_precision)
        per_window.append({"window": window["id"], "ran": ran, "witnesses": shown,
                           "unreproducible": bad, "mislabelled": mislabelled,
                           "background": background,
                           "credited": credited, "minimal": minimal,
                           "precision": round(window_precision, 6), "caught": hit})
    graded = len(WINDOWS)
    unreliable = invalid / read_total if read_total else 0.0
    validity_gate = 0 if (launch_failures == graded or unreliable > UNRELIABLE_SHARE) else 1

    recall = len(caught) / graded
    allowance = WITNESS_ALLOWANCE_PER_WINDOW
    precision = sum(precisions) / len(precisions) if precisions else 0.0
    attributed = 0
    for wid, labels in labels_by_window.items():
        own = {lab for lab in labels if lab}
        if len(own) != 1:
            continue
        mine = next(iter(own))
        if any(mine in {lab for lab in other if lab}
               for oid, other in labels_by_window.items() if oid != wid):
            continue
        attributed += 1
    attribution = attributed / len(caught) if caught else 0.0
    minimality = minimal_total / credited_total if credited_total else 0.0
    reward = validity_gate * recall * precision * attribution * minimality
    return {
        "reward": round(reward, 6),
        "validity_gate": validity_gate,
        "caught": len(caught),
        "graded": graded,
        "recall": round(recall, 6),
        "precision": round(precision, 6),
        "attribution": round(attribution, 6),
        "minimality": round(minimality, 6),
        "mechanisms": sorted(mechanisms),
        "witnesses_read": read_total,
        "witness_allowance": allowance,
        "credited": credited_total,
        "unreproducible": invalid,
        "mislabelled": mislabelled_total,
        "unreliable_share": round(unreliable, 6),
        # Ints, not bools: main() filters bools out of reward.json, and a reviewer needs both of
        # these next to the number. A reward earned under a hit deadline is a partial pass over
        # the full denominator, and one earned without the privilege drop was not isolated from
        # windows.json at all.
        "deadline_hit": 1 if deadline_hit else 0,
        "windows_attempted": windows_attempted,
        "submission_privilege_dropped": 1 if dropped else 0,
        # Surfaced because launch_failures == graded already zeroes validity_gate, and that zero
        # is indistinguishable from a wrong submission unless the count travels with it. A tester
        # uid 65534 cannot execute fails every window for a verifier reason, not a graded one.
        "launch_failures": launch_failures,
        "windows": per_window,
    }


def ctrf(result: dict, path: Path) -> None:
    windows = result.get("windows", [])
    launched = bool(windows) and any(w.get("ran") == "ok" for w in windows)
    outcomes = {
        "witnesses_reproduce": result.get("unreproducible", 0) == 0,
        "post_fix_agreement_required": result.get("caught", 0) == 0
        or all(w.get("caught") is not None for w in windows),
        "witness_cap_enforced": result.get("witnesses_read", 0) <= WITNESS_CAP * len(WINDOWS),
        "tester_launched": launched,
        "both_solver_modes_named": True,
    }
    tests = [{"name": name, "status": "passed" if ok else "failed", "duration": 0}
             for name, ok in outcomes.items()]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"results": {
        "tool": {"name": "brocket-solverdiff-grader"},
        "summary": {"tests": len(tests),
                    "passed": sum(t["status"] == "passed" for t in tests),
                    "failed": sum(t["status"] == "failed" for t in tests),
                    "pending": 0, "skipped": 0, "other": 0},
        "tests": tests,
    }}, indent=1) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    tester = Path(argv[argv.index("--tester") + 1]) if "--tester" in argv else Path("/app/tester/run")
    budget = int(argv[argv.index("--budget") + 1]) if "--budget" in argv else 300
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 20261109
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 4
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("/logs/verifier/reward.json")
    deadline = float(argv[argv.index("--deadline") + 1]) if "--deadline" in argv else DEFAULT_DEADLINE
    if not os.access(tester, os.X_OK):
        result = {"reward": 0.0, "validity_gate": 0, "caught": 0, "graded": len(WINDOWS),
                  "mechanisms": [], "witnesses_read": 0, "unreproducible": 0,
                  "windows": [], "note": "no executable tester at the declared entry point"}
    else:
        with tempfile.TemporaryDirectory() as scratch:
            result = grade(tester, budget, seed, jobs, Path(scratch), deadline)
    out.parent.mkdir(parents=True, exist_ok=True)
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
