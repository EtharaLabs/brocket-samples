from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import random
import subprocess
import sys
import tempfile
import time
from pathlib import Path

MODES = ("no", "globally")
LEAVES = ("()", "u8", "u32", "i32", "String", "bool")
AUTO = ("Send", "Sync")
TRAITS = ("A", "B", "C")


def ty(rng: random.Random, depth: int = 0, param: bool = True) -> str:
    roll = rng.random()
    if param and roll < 0.22:
        return "T"
    if depth >= 2 or roll < 0.5:
        return rng.choice(LEAVES)
    inner = ty(rng, depth + 1, param)
    return rng.choice(
        ("Vec<{}>", "Option<{}>", "Box<{}>", "S<{}>", "&'static {}", "({}, {})".replace("{}, {}", "{0}, {0}"))
    ).format(inner)


def bound(rng: random.Random, assoc: dict[str, str]) -> str:
    name = rng.choice(TRAITS + AUTO)
    if name in assoc and rng.random() < 0.35:
        kind = assoc[name]
        if kind == "gat":
            return f"{name}<Assoc<'static> = {ty(rng)}>"
        return f"{name}<Assoc = {ty(rng)}>"
    if name in TRAITS and rng.random() < 0.15:
        return f"{name}<'static>" if rng.random() < 0.5 else name
    return name


def clause(rng: random.Random, assoc: dict[str, str]) -> str:
    roll = rng.random()
    if roll < 0.32:
        return f"{ty(rng)}: {bound(rng, assoc)}"
    carriers = [t for t in assoc]
    if roll < 0.55 and carriers:
        name = rng.choice(carriers)
        proj = f"<{ty(rng)} as {name}>::Assoc"
        if assoc[name] == "gat":
            proj = f"<{ty(rng)} as {name}>::Assoc<'static>"
        return f"{proj}: {bound(rng, assoc)}"
    if roll < 0.72:
        return f"for<'a> &'a {ty(rng)}: {bound(rng, assoc)}"
    if roll < 0.85:
        return f"T: {bound(rng, assoc)}"
    return f"{ty(rng)}: 'static"


def program(rng: random.Random) -> str:
    assoc = {t: rng.choice(("plain", "gat")) for t in TRAITS if rng.random() < 0.6}
    lines = ["#![allow(dead_code, unused)]", "struct S<T>(T);"]
    for name in TRAITS:
        supers = ""
        if rng.random() < 0.25:
            other = rng.choice([t for t in TRAITS if t != name])
            supers = f": {other}"
        if name not in assoc:
            lines.append(f"trait {name}{supers} {{}}")
        elif assoc[name] == "gat":
            lines.append(f"trait {name}{supers} {{ type Assoc<'a>; }}")
        else:
            lines.append(f"trait {name}{supers} {{ type Assoc; }}")
    if rng.random() < 0.3:
        lines.append(f"struct Field<T>({ty(rng)});".replace("Field<T>(T)", "Field<T>(T)"))
    for _ in range(rng.randint(1, 4)):
        name = rng.choice(TRAITS)
        target = ty(rng)
        generic = "<T>" if "T" in target else ""
        clauses = [clause(rng, assoc) for _ in range(rng.randint(0, 2))] if generic else []
        where = f" where {', '.join(clauses)}" if clauses else ""
        body = ""
        if name in assoc:
            value = ty(rng, param=bool(generic))
            body = f" type Assoc<'a> = {value}; " if assoc[name] == "gat" else f" type Assoc = {value}; "
        lines.append(f"impl{generic} {name} for {target}{where} {{{body}}}")
    uses = " + ".join(bound(rng, assoc) for _ in range(rng.randint(1, 2)))
    lines.append(f"fn need<T: {uses}>() {{}}")
    lines.append(f"pub fn site() {{ need::<{ty(rng, param=False)}>(); }}")
    if rng.random() < 0.25:
        lines.append(f"fn opaque(x: {ty(rng, param=False)}) -> impl Sized {{ x }}")
    if rng.random() < 0.2:
        name = rng.choice(TRAITS)
        lines.append(f"fn obj(x: &dyn {name}) -> &dyn {name} {{ x }}" if name not in assoc else "")
    return "\n".join(l for l in lines if l) + "\n"


def outcome(toolchain: str, path: Path, mode: str, timeout: int = 20) -> str:
    with tempfile.TemporaryDirectory() as scratch:
        argv = ["rustc", f"+{toolchain}", "--edition", "2021", "--crate-type", "lib",
                "--emit=metadata", "-o", f"{scratch}/o.rmeta", f"-Znext-solver={mode}",
                "-Awarnings", str(path)]
        try:
            done = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                                  env={**os.environ, "RUST_BACKTRACE": "0"})
        except subprocess.TimeoutExpired:
            return "hang"
    return {0: "accept", 1: "reject", 101: "ice"}.get(done.returncode, f"exit-{done.returncode}")


def worker(toolchain: str, seed: int, deadline: float, out: Path) -> tuple[int, int]:
    rng, tried, kept = random.Random(seed), 0, 0
    while time.time() < deadline:
        text = program(rng)
        digest = hashlib.sha256(text.encode()).hexdigest()[:16]
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "p.rs"
            path.write_text(text, encoding="utf-8")
            old, new = outcome(toolchain, path, "no"), outcome(toolchain, path, "globally")
        tried += 1
        if old != new:
            kept += 1
            (out / f"{digest}.rs").write_text(text, encoding="utf-8")
    return tried, kept


def main(argv: list[str]) -> int:
    toolchain, seconds = argv[1], float(argv[2])
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 8
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 0
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("naive-out")
    out.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + seconds
    with concurrent.futures.ProcessPoolExecutor(jobs) as pool:
        totals = list(pool.map(worker, [toolchain] * jobs, range(seed, seed + jobs),
                               [deadline] * jobs, [out] * jobs))
    print(json.dumps({"toolchain": toolchain, "tried": sum(t for t, _ in totals),
                      "splits": sum(k for _, k in totals)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
