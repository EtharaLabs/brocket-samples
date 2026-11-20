from __future__ import annotations

import concurrent.futures
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import naive_baseline

KEEP = {"stable", "nightly", "1.95.0", "1.99.0", "nightly-2026-11-08"}
WINDOWS = [
    ("163496", "nightly-2026-10-01", "nightly-2026-10-03"),
    ("163267", "nightly-2026-10-05", "nightly-2026-10-07"),
    ("160982", "nightly-2026-08-14", "nightly-2026-08-15"),
    ("161047", "nightly-2026-08-15", "nightly-2026-08-16"),
    ("156976", "nightly-2026-07-06", "nightly-2026-07-08"),
    ("163159", "nightly-2026-09-22", "nightly-2026-09-24"),
    ("159774", "nightly-2026-07-26", "nightly-2026-07-28"),
    ("160831", "nightly-2026-09-10", "nightly-2026-09-12"),
]


def install(toolchain: str) -> None:
    subprocess.run(["rustup", "toolchain", "install", toolchain, "--profile", "minimal",
                    "--no-self-update"], check=True, capture_output=True, timeout=1800)


def uninstall(toolchain: str) -> None:
    if toolchain not in KEEP:
        subprocess.run(["rustup", "toolchain", "uninstall", toolchain], capture_output=True, timeout=600)


def main(argv: list[str]) -> int:
    seconds = float(argv[1])
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 8
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("gate.json")
    record = []
    for pr, pre, post in WINDOWS:
        workdir = Path(tempfile.mkdtemp(prefix=f"gate-{pr}-"))
        install(pre)
        subprocess.run([sys.executable, "-B", str(Path(__file__).parent / "naive_baseline.py"), pre,
                        str(seconds), "--jobs", str(jobs), "--seed", "500", "--out", str(workdir)],
                       check=True, capture_output=True, timeout=int(seconds) + 900)
        splits = sorted(workdir.glob("*.rs"))
        install(post)

        def verdict(path: Path) -> dict[str, object] | None:
            before = {m: naive_baseline.outcome(pre, path, m, timeout=10) for m in naive_baseline.MODES}
            after = {m: naive_baseline.outcome(post, path, m, timeout=10) for m in naive_baseline.MODES}
            if before["no"] != before["globally"] and after["no"] == after["globally"]:
                return {"program": path.read_text(encoding="utf-8"),
                        "pre": f"{before['no']}/{before['globally']}",
                        "post": f"{after['no']}/{after['globally']}"}
            return None

        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            flips = [row for row in pool.map(verdict, splits) if row is not None]
        record.append({"pr": pr, "pre": pre, "post": post, "sampled_splits": len(splits),
                       "flips": len(flips), "reached": bool(flips), "witnesses": flips[:3]})
        print(f"#{pr}: {len(splits)} splits sampled, {len(flips)} flip -> "
              f"{'REACHED (exclude)' if flips else 'survives'}", flush=True)
        out.write_text(json.dumps(record, indent=1), encoding="utf-8")
        shutil.rmtree(workdir, ignore_errors=True)
        uninstall(pre)
        if post not in {w[1] for w in WINDOWS}:
            uninstall(post)
    reached = [r["pr"] for r in record if r["reached"]]
    print(json.dumps({"windows": len(record), "reached_by_naive": reached,
                      "surviving": [r["pr"] for r in record if not r["reached"]]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
