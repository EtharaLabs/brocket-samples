# TRUTH

The task is a differential tester between rustc's old and next-generation trait solvers. The old solver is `-Znext-solver=no` and the
next-generation solver is `-Znext-solver=globally`. pull request 160619, merged 2026-08-21, made -Znext-solver=globally the nightly default, so a comparison against the bare default compares the next solver with itself on every graded toolchain after that date. Both modes are therefore named explicitly everywhere.
pull request 161491, merged 2026-10-04, removed old-solver coherence, so from that nightly on -Znext-solver=coherence and =no behave identically.

## What counts as a disagreement

The outcome classes are accept, reject, ice, hang. the class is taken from the compiler's exit status: 0 accept, 1 reject, 101 ice, and a run that does not finish inside the timeout is hang. A diagnostic difference inside one class is not a disagreement, because the two solvers differ in wording by design.

## The graded set

7 bugs across 5 mechanisms: assoc-type-normalization-in-cycle, canonicalization-infer-vars, coherence-negative-reasoning, higher-ranked-bounds, inductive-vs-coinductive-cycle.

| window | fix | mechanism | pre-fix | post-fix | observed | reference family | witnesses |
| --- | --- | --- | --- | --- | --- | --- | --- |
| W1 | rust-lang/rust#163496 | inductive-vs-coinductive-cycle | `nightly-2026-09-30` | `nightly-2026-10-02` | pre reject/accept, post reject/reject | `cycle_auto` | 16 |
| W2 | rust-lang/rust#160982 | canonicalization-infer-vars | `nightly-2026-08-14` | `nightly-2026-08-15` | pre accept/reject, post accept/accept | `canon_region` | 4 |
| W3 | rust-lang/rust#161047 | assoc-type-normalization-in-cycle | `nightly-2026-08-15` | `nightly-2026-08-16` | pre reject/accept, post reject/reject | `opaque_implied` | 3 |
| W4 | rust-lang/rust#163159 | assoc-type-normalization-in-cycle | `nightly-2026-09-22` | `nightly-2026-09-24` | pre reject/accept, post reject/reject | `cycle_proj` | 4 |
| W5 | rust-lang/rust#159774 | inductive-vs-coinductive-cycle | `nightly-2026-07-27` | `nightly-2026-07-28` | pre hang/reject, post reject/reject | `cycle_gat` | 2 |
| W6 | rust-lang/rust#160831 | higher-ranked-bounds | `nightly-2026-09-10` | `nightly-2026-09-11` | pre reject/accept, post reject/reject | `hrtb_object` | 4 |
| W7 | rust-lang/rust#163267 | coherence-negative-reasoning | `nightly-2026-10-05` | `nightly-2026-10-07` | pre reject/accept, post reject/reject | `coherence_hrtb` | 4 |

Each window is the narrowest nightly pair that brackets its fix, so a second solver fix
landing in the same span cannot be credited by the same witness.

## The reference tester

It walks 9 structural families emitting 72 programs, and runs in about
2 seconds per toolchain. On `nightly-2026-11-08`, which carries every graded fix,
it reports 0 witnesses. every witness is compiled twice under each mode before it is reported, so a flaky split is dropped rather than claimed.

It catches all 7 graded bugs, each through one family: 163496 through `cycle_auto`, 160982 through `canon_region`, 161047 through `opaque_implied`, 163159 through `cycle_proj`, 159774 through `cycle_gat`, 160831 through `hrtb_object`, 163267 through `coherence_hrtb`.

## The naive baseline, and what it excluded

The baseline samples from a grammar covering 12 construct families
(generic structs with fields, traits with associated types, generic associated types, supertrait lists, blanket and concrete impls, where-clauses over bounds and projections, associated-type bindings, higher-ranked references, explicit outlives bounds, trait objects, opaque return types, the auto traits) with none: each construct is sampled independently and never composed deliberately into a cycle, an overlap, an escaping binder, or a recursing projection.
It is given 300 seconds per window on 8 workers at seed 500.

It reached 1 candidates, and each left the graded set:

| fix | mechanism | splits sampled | flips | why it was excluded |
| --- | --- | --- | --- | --- |
| rust-lang/rust#156976 | canonicalization-infer-vars | 35 | 0 | both recorded flips were timeout artifacts: the next solver takes 39.2s and 36.2s pre-fix against the gate 20s limit and 5.0s and 2.4s post-fix, so the fix is a speedup and both solvers reject on both toolchains. It stays out because the reference tester finds only one attributable witness against 41 background, and its mechanism is already carried by W2. |

It reached none of the graded bugs:

| window | splits sampled | flips |
| --- | --- | --- |
| W1 | 30 | 0 |
| W2 | 32 | 0 |
| W3 | 34 | 0 |
| W4 | 37 | 0 |
| W5 | 39 | 0 |
| W6 | 36 | 0 |
| W7 | 9 | 0 |

## Limits of this record

the reference tester catches zero witnesses on every reserve candidate, because each is a mechanism no structural family models. The graded set therefore has no fallback, and it is exactly the set the reference's families reach.

the old solver overflows with E0275 on recursive blanket impls on every nightly measured, including the development toolchain, and the solvers carry documented intentional differences. Neither class flips across any window, so neither credits a bug, and both compete for the witness cap.
