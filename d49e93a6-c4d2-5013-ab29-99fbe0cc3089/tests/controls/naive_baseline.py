"""The naive baseline: enumerate-only, no model of where a port goes wrong, broad syntactic coverage.

    python3 naive_baseline.py TOOLCHAIN SECONDS [--jobs N] [--seed N] [--out DIR]

The grammar reaches every construct a graded witness uses: object and union type aliases, arrays,
interfaces with properties, methods and accessors, repeated interface names, numeric enums with
NaN and Infinity initialisers, declared bindings, for-of loops, `// @ts-ignore`, generic functions
with const and defaulted type parameters, conditional types, mapped types with `as` clauses,
`keyof`, `using` as an identifier and as a declaration, classes, element access and narrowing
conditions. What it lacks is a model: each construct is sampled independently and never composed
on purpose into the shape a checker port gets wrong. A graded window this reaches is a window that
needs no reasoning about the port, and the gate excludes it.

Every program is checked by the grader's own `compile_once`, under typescript@6.0.3 and TOOLCHAIN;
a program whose classes differ is written to DIR.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import random
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, "/tests/grader")

import grade  # noqa: E402

NAMES = ("A", "B", "Foo", "E")
PROPS = ("a", "b", "x", "tableName")
LEAVES = ("string", "number", "boolean", "never", "unknown", "any", "'a'", "'x'", "1")


def ty(rng: random.Random, depth: int = 0) -> str:
    roll = rng.random()
    if depth >= 2 or roll < 0.45:
        return rng.choice(LEAVES + NAMES[:2])
    if roll < 0.6:
        return f"{ty(rng, depth + 1)}[]"
    if roll < 0.75:
        return f"{ty(rng, depth + 1)} | {ty(rng, depth + 1)}"
    if roll < 0.85:
        return f"{{ {rng.choice(PROPS)}: {ty(rng, depth + 1)} }}"
    if roll < 0.93:
        return f"keyof {ty(rng, depth + 1)}"
    return f"{ty(rng, depth + 1)} extends {ty(rng, depth + 1)} ? {ty(rng, depth + 1)} : {ty(rng, depth + 1)}"


def member(rng: random.Random) -> str:
    name = rng.choice(PROPS)
    roll = rng.random()
    if roll < 0.55:
        return f"    {name}: {ty(rng)};"
    if roll < 0.7:
        return f"    get {name}(): {ty(rng)};"
    if roll < 0.85:
        return f"    set {name}(v: {ty(rng)});"
    return f"    {name}(): {ty(rng)};"


def statement(rng: random.Random) -> str:
    roll = rng.random()
    name = rng.choice(NAMES)
    if roll < 0.12:
        return f"type {name} = {ty(rng)};"
    if roll < 0.26:
        body = "\n".join(member(rng) for _ in range(rng.randint(1, 3)))
        return f"interface {name} {{\n{body}\n}}"
    if roll < 0.34:
        values = [rng.choice(("0", "1", "NaN", "Infinity", "-1", "'s'")) for _ in range(rng.randint(1, 3))]
        body = ",\n".join(f"  M{i} = {v}" for i, v in enumerate(values))
        return f"enum {name}{rng.randint(0, 9)} {{\n{body}\n}}"
    if roll < 0.44:
        return f"declare let {rng.choice(('data', 'using', 'v', 'k'))}: {ty(rng)};"
    if roll < 0.52:
        prefix = "// @ts-ignore\n" if rng.random() < 0.4 else ""
        return f"{prefix}for (const item of {rng.choice(('data', 'v', '[1, 2]', '[] as any[]'))}) {{\n  item.{rng.choice(PROPS)};\n}}"
    if roll < 0.6:
        const = "const " if rng.random() < 0.5 else ""
        default = f" = {ty(rng)}" if rng.random() < 0.5 else ""
        return f"declare function f{rng.randint(0, 3)}<{const}T extends {ty(rng)}{default}>(x: {{ p?: T | {ty(rng)} }}): T;"
    if roll < 0.66:
        return f"f{rng.randint(0, 3)}({{ p: {rng.choice(('1', '\"x\"', '\"x\" as never', 'undefined'))} }});"
    if roll < 0.74:
        clause = rng.choice(("K", "K extends 'a' ? never : K", "[K] extends ['a'] ? 'x' : 'y'", "`get${K}`"))
        return f"type M{rng.randint(0, 3)}<T> = {{ [K in keyof T & string as {clause}]: {ty(rng)} }};"
    if roll < 0.8:
        return rng.choice(("using\nv;", "using;", "{ using r = null; }", "declare let r: keyof M0<{ a: 1 }>;"))
    if roll < 0.88:
        return (f"class C{rng.randint(0, 2)} {{ constructor(public {rng.choice(PROPS)}: {ty(rng)}) {{}} }}\n"
                f"declare const o: unknown;\nif (o instanceof C0 || (o as any).constructor === C0) {{ o; }}")
    if roll < 0.95:
        return (f"declare const g: number[][]; declare const n: number | undefined;\n"
                f"if (n) {{ for (const [i, j] of [[0, 1]]) {{ if (g[n + i][j] === 0) {{}} }} }}")
    return f"export const z{rng.randint(0, 9)}: {ty(rng)} = {rng.choice(('1', '\"x\"', 'null!', 'undefined!'))};"


def program(rng: random.Random) -> str:
    return "\n".join(statement(rng) for _ in range(rng.randint(2, 6))) + "\nexport {};\n"


def worker(toolchain: str, seed: int, deadline: float, out: Path) -> tuple[int, int]:
    rng, tried, kept = random.Random(seed), 0, 0
    while time.time() < deadline:
        text = program(rng)
        old, new = grade.compile_once(grade.BASELINE, text), grade.compile_once(toolchain, text)
        tried += 1
        if old != new:
            kept += 1
            (out / f"{hashlib.sha256(text.encode()).hexdigest()[:16]}.ts").write_text(text, encoding="utf-8")
    return tried, kept


def main(argv: list[str]) -> int:
    toolchain, seconds = argv[1], float(argv[2])
    jobs = int(argv[argv.index("--jobs") + 1]) if "--jobs" in argv else 4
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 0
    out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("naive-out")
    out.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + seconds
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        totals = list(pool.map(worker, [toolchain] * jobs, range(seed, seed + jobs),
                               [deadline] * jobs, [out] * jobs))
    print(json.dumps({"toolchain": toolchain, "tried": sum(t for t, _ in totals),
                      "splits": sum(k for _, k in totals)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
