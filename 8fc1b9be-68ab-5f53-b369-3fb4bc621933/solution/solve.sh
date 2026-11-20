#!/bin/sh
# Reference solution for the rustc MIR bounds-check elision task.
#
# Installs the BoundsCheckElision pass into the compiler and registers it in the MIR
# optimization pipeline immediately before SimplifyConstCondition::Final, which
# is the pass that turns an assert with a constant-true condition into a goto.
set -eu

SOLUTION_DIR=${SOLUTION_DIR:-/solution}
RUST_DIR=${RUST_DIR:-/app/rust}

cp "$SOLUTION_DIR/bounds_check_elision.rs" "$RUST_DIR/compiler/rustc_mir_transform/src/bounds_check_elision.rs"

python3 - "$RUST_DIR" <<'PY'
import sys
from pathlib import Path

lib = Path(sys.argv[1], "compiler/rustc_mir_transform/src/lib.rs")
text = lib.read_text(encoding="utf-8")

declare_anchor = "    mod ssa_range_prop: SsaRangePropagation;\n"
declare_new = "    mod bounds_check_elision: BoundsCheckElision;\n"
if declare_new not in text:
    if declare_anchor not in text:
        raise SystemExit("declare anchor not found: ssa_range_prop module line")
    text = text.replace(declare_anchor, declare_anchor + declare_new, 1)

# Must run after JumpThreading: before it, a desugared `for` loop puts the assert behind an
# Option discriminant switch whose block has both guard paths as predecessors.
pipeline_anchor = "            &o1(simplify_branches::SimplifyConstCondition::Final),\n"
pipeline_new = "            &bounds_check_elision::BoundsCheckElision,\n"
if pipeline_new not in text:
    if pipeline_anchor not in text:
        raise SystemExit("pipeline anchor not found: SimplifyConstCondition::Final")
    text = text.replace(pipeline_anchor, pipeline_new + pipeline_anchor, 1)

lib.write_text(text, encoding="utf-8")
print("registered BoundsCheckElision in the MIR pipeline")
PY

cd "$RUST_DIR"
python3 x.py build --stage 1 library
