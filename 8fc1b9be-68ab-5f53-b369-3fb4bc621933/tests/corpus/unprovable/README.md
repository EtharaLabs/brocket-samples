# Unprovable at this pipeline position

A case here is always-safe by construction, so a bounds check on it is genuinely redundant,
but no intraprocedural analysis of the optimized MIR can prove it. It is kept for the record
and excluded from scoring, because the oracle must be able to reach the full score.

nested_bound_from_outer.rs: the inner loop is `0..=i`, and `RangeInclusive::next` is not
inlined at this point in the pipeline. The yielded index arrives as the payload of an Option
returned by an opaque call, so the body holds no comparison relating it to the outer bound.
Proving it needs the callee inlined or an interprocedural summary, neither of which is the
bounds-check reasoning this task asks for. Exclusive `Range` is inlined, which is why
plain_forward_loop is scored and this is not.

This exclusion is worth stating plainly: the case was written by reasoning about what the
Rust source guarantees, but a check is only removable here if the guarantee survives into
the MIR this pass sees. Whether a library call is inlined at mir-opt-level 2 decides that,
and `Range` is inlined where `RangeInclusive::next` is not.

`min_clamped_index.rs` was once excluded here for the same reason, on the belief that
`<usize as Ord>::min` is not inlined at this position. It is, so the clamped value is
relatable to the shortened bound in the body and the case is provable. It now lives in
`should_remove/` and is scored (`expected.json`: `"min_clamped_index.rs": "solved"`, weight
1). Nothing in this directory is scored.
