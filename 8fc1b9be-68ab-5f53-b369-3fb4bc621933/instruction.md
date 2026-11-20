# Eliminate redundant bounds checks in the MIR optimizer

You are working in a checkout of the Rust compiler at `/app/rust`. A stage-1 compiler is
already built, so your edit and rebuild loop is incremental.

## The objective

Under optimization, `rustc` emits a bounds-check assertion for every slice and array index
expression. Many of those assertions can never fail, and the optimizer should remove them.
Extend the MIR optimizer so that it does.

A bounds check may be removed only when the index is provably within bounds. Proofs may use
facts in the current function and sound summaries derived from callees, including callees that
are not inlined. A bounds check must be kept whenever the index can reach or exceed the length
on any execution path.

Your pass must take effect at `-O` (`-Zmir-opt-level=2`) and the MIR it produces must be valid
under `-Zvalidate-mir`.

## Where to work

Edit under `compiler/rustc_mir_transform/`. The existing pass `ssa_range_prop.rs` already
removes a bounds check when an identical comparison dominates the index, and it carries notes
on what it does not yet do. You may extend it, replace it, or add a new pass to the pipeline.

Build with:

    python3 x.py build --stage 1 library

## Rules

- Removing a bounds check that can fail is a memory-safety defect and must never happen.
- Keep every change inside `compiler/`, and do not add a dependency: `Cargo.lock` cannot move.
- There is no network. The cargo registry is cached and `CARGO_NET_OFFLINE` is set.
- Do not remove or weaken an upstream test.
- Do not change how the bounds check is lowered in `rustc_mir_build` so that no assertion is
  emitted in the first place. The property being asked for is elimination of a provably
  redundant assertion by the optimizer, not suppression of its emission.
