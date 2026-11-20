#!/usr/bin/env python3
"""Measure the reference pass against the corpus: soundness gate and generalization.

Generalization counts checks, not files, and weights each check by its mechanism class so that
breadth of index arithmetic cannot substitute for the reasoning the task is about. Removing
every check still scores 1.0; the weighting only shapes partial credit.
"""
import json
import os
import pathlib
import platform
import sys

sys.path.insert(0, "/t")
import count_bounds_checks as c  # noqa: E402

# bootstrap names its build directory after the host triple, so this path is
# architecture-dependent and cannot be a constant on a multi-platform image.
_HOST_TRIPLE = {
    "x86_64": "x86_64-unknown-linux-gnu",
    "aarch64": "aarch64-unknown-linux-gnu",
    "arm64": "aarch64-unknown-linux-gnu",
}
_machine = platform.machine()
if _machine not in _HOST_TRIPLE:
    sys.exit("unsupported machine for stage-1 rustc: %s" % _machine)

RUSTC = os.environ.get(
    "RUSTC", "/app/rust/build/%s/stage1/bin/rustc" % _HOST_TRIPLE[_machine]
)
expected = json.load(open("/t/corpus/expected.json"))

violations = []
print("== must_keep: a check removed here is unsound ==")
for name, base in sorted(expected["must_keep"].items()):
    got, _ = c.count(RUSTC, pathlib.Path("/t/corpus/must_keep", name))
    ok = got >= base
    if not ok:
        violations.append(name)
    print("  %-40s base=%d now=%d %s" % (name, base, got, "ok" if ok else "UNSOUND"))

removable = 0
removed = 0
classes = expected["mechanism_class"]
mass = expected["class_mass"]
per_class = {k: [0, 0] for k in mass}
print()
print("== should_remove: credit per check removed ==")
for name, base in sorted(expected["should_remove"].items()):
    got, _ = c.count(RUSTC, pathlib.Path("/t/corpus/should_remove", name))
    gone = max(0, base - got)
    removable += base
    removed += gone
    slot = per_class[classes[name]]
    slot[0] += gone
    slot[1] += base
    print("  %-44s %-6s base=%d now=%d removed=%d/%d" % (
        name, classes[name], base, got, gone, base))

soundness = 0.0 if violations else 1.0
generalization = sum(mass[k] * (g / t) for k, (g, t) in per_class.items() if t)
flat = removed / removable if removable else 0.0
print()
print("  soundness_gate  = %s%s" % (soundness, "  VIOLATED: %s" % violations if violations else ""))
for k, (g, t) in sorted(per_class.items()):
    print("  %-7s %2d/%2d checks = %.4f  x mass %.2f = %.4f" % (
        k, g, t, (g / t) if t else 0.0, mass[k], mass[k] * ((g / t) if t else 0.0)))
print("  unweighted      = %d/%d checks = %.4f" % (removed, removable, flat))
print("  generalization (class-weighted) = %.4f" % generalization)
print("  reward (pre-regression) = %.4f" % (soundness * generalization))
