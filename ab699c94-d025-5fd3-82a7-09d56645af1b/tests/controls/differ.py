from __future__ import annotations

import concurrent.futures
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

MODES = ("no", "globally")
EDITION = "2021"
COMPILE_TIMEOUT = 60


def load_generator(path: str | Path) -> Any:
    resolved = Path(path).expanduser().resolve()
    if not resolved.is_file():
        raise FileNotFoundError(
            f"no generator at {resolved}: pass the path of a module exposing programs()"
        )
    spec = importlib.util.spec_from_file_location("solverdiff_generator", resolved)
    if spec is None or spec.loader is None:
        raise ImportError(f"could not load a module spec from {resolved}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["solverdiff_generator"] = module
    spec.loader.exec_module(module)
    if not hasattr(module, "programs"):
        raise AttributeError(f"{resolved} exposes no programs()")
    return module


def outcome(toolchain: str, source: str, mode: str, timeout: int = COMPILE_TIMEOUT) -> str:
    with tempfile.TemporaryDirectory() as scratch:
        path = Path(scratch) / "p.rs"
        path.write_text(source, encoding="utf-8")
        argv = [
            "rustc", f"+{toolchain}", "--edition", EDITION, "--crate-type", "lib",
            "--emit=metadata", "-o", f"{scratch}/o.rmeta", f"-Znext-solver={mode}",
            "-Awarnings", str(path),
        ]
        try:
            done = subprocess.run(
                argv, capture_output=True, text=True, timeout=timeout,
                env={**os.environ, "RUST_BACKTRACE": "0"},
            )
        except subprocess.TimeoutExpired:
            return "hang"
    return {0: "accept", 1: "reject", 101: "ice"}.get(done.returncode, "ice")


def pair(toolchain: str, source: str, timeout: int = COMPILE_TIMEOUT) -> tuple[str, str]:
    return (
        outcome(toolchain, source, "no", timeout),
        outcome(toolchain, source, "globally", timeout),
    )


def run(
    toolchain: str, generator: Any, jobs: int = 6, timeout: int = COMPILE_TIMEOUT
) -> list[dict]:
    programs = list(generator.programs())

    def sweep(item: tuple[str, str, str]) -> dict:
        family, ident, source = item
        old, nxt = pair(toolchain, source, timeout)
        return {"id": ident, "family": family, "split": old != nxt, "old": old, "next": nxt}

    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        return list(pool.map(sweep, programs))


if __name__ == "__main__":
    import json

    if "--generator" not in sys.argv:
        raise SystemExit("usage: differ.py TOOLCHAIN --generator PATH [--jobs N]")
    tc = sys.argv[1]
    gen = load_generator(sys.argv[sys.argv.index("--generator") + 1])
    n = int(sys.argv[sys.argv.index("--jobs") + 1]) if "--jobs" in sys.argv else 6
    rows = run(tc, gen, jobs=n)
    print(json.dumps({"toolchain": tc, "programs": len(rows),
                      "splits": sum(r["split"] for r in rows)}, indent=1))
