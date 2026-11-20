## Iterative Evaluation Mode

You are working with iterative test feedback. After implementing code, you can submit your work for evaluation at any time to see which tests pass and which fail, then iterate based on the results.

### How to Test Your Code

- Run `sforge-submit` to submit your current code for evaluation. It will package the files, send them to the judge server, and return results showing score, pass rate, and a summary of findings.
- Run `sforge-submit --details` to submit and see detailed per-test results.
- Run `sforge-submit --list` to view all previous submissions and their scores for this run.

You should use these regularly to check your progress and identify issues.

### Submitted Files

Only the following paths are submitted for evaluation: `compiler/`

**Keep these files in a compilable/runnable state at all times.** A background process periodically auto-evaluates your code — if the submitted files are broken, incomplete, or contain syntax errors at that moment, the auto-evaluation will fail. Write changes to disk promptly and ensure the submitted files always represent your current best solution.

### Submission Limits

- There is a **minimum interval of 600s** between submissions.

### Network Environment

**This environment has NO internet access.** Only the judge server and the AI API are reachable. Do not attempt to download packages, fetch remote resources, or access external URLs — all dependencies are pre-installed in the workspace.

### Strategy

- **Implement incrementally**: Complete one module/project at a time
- **Read test feedback carefully**: Failed test names often hint at what's broken
- **Iterate**: Fix failing tests based on the feedback, then submit again

### Scoring

- Your **best score** across all submissions is your final score
- You don't lose points for failed attempts — experimentation is encouraged

---

# Eliminate redundant bounds checks in the MIR optimizer

You are working in a checkout of the Rust compiler at `/app/rust`. A stage-1 compiler is
already built, so your edit and rebuild loop is incremental.

## The objective

Under optimization, `rustc` emits a bounds-check assertion for every slice and array index
expression. Many of those assertions can never fail, and the optimizer should remove them.
Extend the MIR optimizer so that it does.

A bounds check may be removed only when the index is provably within bounds from facts
available in the same function body. A bounds check must be kept whenever the index can reach
or exceed the length on any execution path.

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

SUBMISSION AND ENVIRONMENT NOTES

- Work only under compiler/. Only that subtree is collected from your submission.
- The checkout ships upstream rustc's own AGENTS.md and CLAUDE.md. Those are the rust-lang
  contribution guides, not this task's instructions. This prompt is the task contract.
- You own the checkout at /app/rust and its build output, so your edit and rebuild loop needs
  no privilege escalation.

