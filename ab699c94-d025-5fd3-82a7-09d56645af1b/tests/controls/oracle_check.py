from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import differ

KEEP = {"stable", "nightly", "1.95.0", "1.99.0", "nightly-2026-11-08"}
WINDOWS = [
    ("163496", "nightly-2026-09-30", "nightly-2026-10-02", "inductive-vs-coinductive-cycle"),
    ("160982", "nightly-2026-08-14", "nightly-2026-08-15", "canonicalization-infer-vars"),
    ("161047", "nightly-2026-08-15", "nightly-2026-08-16", "assoc-type-normalization-in-cycle"),
    ("163159", "nightly-2026-09-22", "nightly-2026-09-24", "assoc-type-normalization-in-cycle"),
    ("159774", "nightly-2026-07-27", "nightly-2026-07-28", "inductive-vs-coinductive-cycle"),
    ("160831", "nightly-2026-09-10", "nightly-2026-09-11", "higher-ranked-bounds"),
    ("163267", "nightly-2026-10-05", "nightly-2026-10-07", "coherence-negative-reasoning"),
]


def install(toolchain: str) -> None:
    subprocess.run(
        ["rustup", "toolchain", "install", toolchain, "--profile", "minimal", "--no-self-update"],
        check=True, capture_output=True, timeout=1800,
    )


def uninstall(toolchain: str) -> None:
    if toolchain not in KEEP:
        subprocess.run(["rustup", "toolchain", "uninstall", toolchain], capture_output=True, timeout=600)


def main(argv: list[str]) -> int:
    if "--generator" not in argv:
        print("usage: oracle_check.py --generator PATH [--jobs N] [--out FILE]", file=sys.stderr)
        return 2
    generator = differ.load_generator(argv[argv.index("--generator") + 1])
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 6
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("oracle-check.json")
    cache: dict[str, dict[str, dict]] = {}
    record = []
    for pr, pre, post, mechanism in WINDOWS:
        for toolchain in (pre, post):
            if toolchain not in cache:
                install(toolchain)
                rows = differ.run(toolchain, generator, jobs=jobs)
                cache[toolchain] = {r["id"]: r for r in rows}
                print(f"{toolchain}: {sum(r['split'] for r in rows)} splits of {len(rows)}", flush=True)
        caught = []
        for ident, before in cache[pre].items():
            after = cache[post][ident]
            if before["split"] and not after["split"]:
                caught.append({
                    "id": ident, "family": before["family"],
                    "pre": f"{before['old']}/{before['next']}",
                    "post": f"{after['old']}/{after['next']}",
                })
        record.append({"pr": pr, "mechanism": mechanism, "pre": pre, "post": post,
                       "caught": bool(caught), "witnesses": caught})
        print(f"#{pr} {mechanism}: {'CAUGHT ' + str(len(caught)) if caught else 'MISSED'}", flush=True)
        out.write_text(json.dumps(record, indent=1), encoding="utf-8")
    for toolchain in cache:
        uninstall(toolchain)
    hit = [r for r in record if r["caught"]]
    print(json.dumps({"graded": len(record), "caught": len(hit),
                      "mechanisms": sorted({r["mechanism"] for r in hit})}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
