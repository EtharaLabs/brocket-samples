# Golden trajectory

The ordered path a correct solution takes through `instruction.md`, with the state each step
establishes, the drift it must survive, and the checker that step satisfies. The committed
checker set is exactly `generalization`, `soundness_gate`, and `regression_gate`, the three
keys `tests/grade.py` writes into the reward artifact.

## Steps

1. Read the pipeline. Locate `compiler/rustc_mir_transform/src/lib.rs` and find where the
   optimization pipeline is declared. Establishes: the insertion point is known. Must survive:
   the pass list is long and ordering-sensitive, and a pass placed before `JumpThreading` sees a
   desugared `for` loop whose assert still sits behind an `Option` discriminant switch. Binds
   the deliverable `a registered MIR pass`. Checker: `generalization`.

2. Author the pass. Add a module under `compiler/rustc_mir_transform/src/` implementing
   `MirPass`, gated on `mir_opt_level() > 1`. Establishes: the compiler builds with the pass
   present. Must survive: the crate denies `rustc::potential_query_instability`, so a hash set
   holding anything a query result depends on is rejected at build time. Binds the deliverable
   `a registered MIR pass`. Checker: `regression_gate`.

3. Carry the relation, not the boolean. Implement a forward must-analysis whose facts are
   ordered relations between places, entering a block only when every reachable predecessor
   offers them. Establishes: a loop guard's relation reaches the assert several blocks later.
   Must survive: the upstream `SsaRangePropagation` records only singleton equalities over SSA
   locals, and a loop counter is a mutable local by construction, so reusing it proves nothing.
   Binds the red-line `no assert may be removed without a proof in the same body`. Checker:
   `generalization`.

4. Follow the index through the iterator. Track relations over enum payloads, not locals alone,
   because `for i in 0..n` launders the index through `Some(copy _10)` and reads it back through
   a downcast. Establishes: a `for` loop proves, not only a `while` loop. Must survive: the
   payload must be read back only under the variant it was built with. Binds the deliverable
   `removal of the always-safe checks`. Checker: `generalization`.

5. Kill on write, carry on copy. Drop every relation naming a place when it is assigned,
   including through one of its fields, and carry a source's relations onto the target of a
   copy. Establishes: a value captured before its source advances keeps what was proved. Must
   survive: a loop captures the counter and then increments it, and a guard that tested a stale
   value proves nothing. Binds the red-line `a relation never crosses an assignment that could
   falsify it`. Checker: `soundness_gate`.

6. Bound the work. Cap the relation set and give the solver a step budget, and on exhausting it
   prove nothing rather than returning what was computed so far. Establishes: the pass
   terminates on every body. Must survive: relation sets here are refined downward from an
   optimistic start, so an unfinished fixpoint can still name a relation some predecessor does
   not offer, and keeping those would remove a fallible check. A real crate compares far more
   than a corpus case does. Binds the red-line `the compiler must still build`. Checker:
   `regression_gate`.

7. Rewrite the terminator. Replace a proved `Assert` with a `Goto` to its success target.
   Establishes: the check is gone from the optimized MIR. Must survive: the panic edge becomes
   unreachable, and the result must still pass `-Zvalidate-mir`. Binds the deliverable
   `removal of the always-safe checks`. Checker: `regression_gate`.

## Rejected routes

Each route below is a known-wrong control the feasibility bundle carries, and Phase verify
measured its rejection.

- Strip every bounds-check assert without proving anything. Rejected by `control_remove_all.rs`
  through `solve_remove_all.sh`: the soundness corpus loses checks that can fail, and the
  behaviour probe finds that a genuinely out-of-range access stopped panicking. Both
  `soundness_gate` and `regression_gate` refuse it.

- Register a pass that proves nothing, so the wiring is present and the reasoning is not.
  Rejected by `control_noop.rs` through `solve_noop.sh`: nothing is removed, so
  `generalization` pays nothing. Wiring alone earns no credit.

- Change nothing and submit the upstream compiler. Rejected by `solve_empty.sh`: every check
  the scored cases carry is still there, so `generalization` pays nothing.

- Remove a check whose index comes from an opaque call. Refused by construction rather than by
  a control: the one case under `tests/corpus/unprovable/`, `nested_bound_from_outer.rs`, is
  always safe in Rust source and carries no relation in the MIR this pass sees, because
  `RangeInclusive::next` is not inlined at this point in the pipeline. It is excluded from
  scoring, so a solution that claims it has guessed rather than proved.

  `min_clamped_index.rs` was once excluded here on the same reasoning, on the belief that
  `<usize as Ord>::min` is not inlined either. It is, so the clamped value is relatable to the
  shortened bound within the body. That case now lives in `should_remove/` and is scored at
  weight 1, which is why the corpus holds 98 scored files carrying 99 checks.
