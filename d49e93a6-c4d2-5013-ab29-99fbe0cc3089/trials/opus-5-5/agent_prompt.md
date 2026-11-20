## Iterative Evaluation Mode

You are working with iterative test feedback. After implementing code, you can submit your work for evaluation at any time to see which tests pass and which fail, then iterate based on the results.

### How to Test Your Code

- Run `sforge-submit` to submit your current code for evaluation. It will package the files, send them to the judge server, and return results showing score, pass rate, and a summary of findings.
- Run `sforge-submit --details` to submit and see detailed per-test results.
- Run `sforge-submit --list` to view all previous submissions and their scores for this run.

You should use these regularly to check your progress and identify issues.

### Submitted Files

Only the following paths are submitted for evaluation: `tester/`

**Keep these files in a compilable/runnable state at all times.** A background process periodically auto-evaluates your code — if the submitted files are broken, incomplete, or contain syntax errors at that moment, the auto-evaluation will fail. Write changes to disk promptly and ensure the submitted files always represent your current best solution.

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

### Execution Budget

- Total budget for this task: 12h 0m of agent execution time.
- The run proceeds in ROUNDS. A round ending is NOT the end of the run — you will be resumed until the budget is spent.
- Your best submission is retained automatically. You never lose a good result by continuing to experiment.
- Live state is in `/tmp/sforge_budget.json` (`remaining_seconds`, `round`, `best_score`). Read it whenever you resume.
- Do NOT stop early, do NOT sleep to pass time, and do NOT emit filler text. If you believe you have converged, that is a signal to try a materially DIFFERENT and testable hypothesis, not to stop.
- Negative results are useful. Record what you ruled out so you do not repeat it.

# A differential tester for TypeScript's two checkers

TypeScript now ships two implementations of its type checker. `typescript@6.0.3` is the last
release of the original checker, written in TypeScript and run on Node. The 7.x line is a port of
that checker to Go, published as dated development builds while the port converges. The port is
meant to agree with 6.0.3 on every program, so a program that one checker accepts and the other
rejects, or that crashes or hangs one of them, is almost always a bug in the port. Upstream fixes
such divergences continuously, and each fix is a program that used to split the two checkers and
no longer does.

Build the tool that finds them.

## What to build

A differential tester at `/app/tester/` that, given one Go-native toolchain, generates TypeScript
programs, checks each under `typescript@6.0.3` and under that toolchain, and reports the programs on
which they disagree.

It must be executable as:

    /app/tester/run --toolchain <name> --budget <seconds> --seed <n> --out <file>

`--toolchain` names a Go-native build; it runs as `/opt/ts/<name>/bin/tsc`. The baseline checker is
always `/opt/ts/tsc6/bin/tsc`. Your tester must not assume the Go build installed here: it will be
run against several others. `--budget` is the wall-clock second count your run may take; a run that
overruns it by more than 10 percent is void. `--seed` fixes your generator's randomness, and the
same seed must produce the same report. `--out` is where you write the report.

Every program is checked as a single file named `main.ts` in an otherwise empty directory, with
exactly this invocation and no `tsconfig.json`:

    tsc --noEmit --strict --target es2022 --module esnext --moduleResolution bundler main.ts

## The report

`--out` receives one JSON object:

    {
      "witnesses": [
        {
          "id": "<your own stable identifier>",
          "source": "<the complete contents of main.ts, as one string>",
          "old": "accept" | "reject" | "crash" | "hang",
          "new": "accept" | "reject" | "crash" | "hang",
          "mechanism": "<your label for what this exercises; see Discrimination below>"
        }
      ]
    }

`old` is the outcome under `typescript@6.0.3` and `new` the outcome under the named toolchain, where
the outcome classes are:

- `accept`: the checker exits 0
- `reject`: the checker exits non-zero and prints at least one `error TS<code>` diagnostic, and
  nothing in its output shows the checker itself failing
- `crash`: the checker fails rather than judging your program: a Go `panic:` or `fatal error:`, an
  uncaught JavaScript exception or stack trace, or a non-zero exit with no diagnostic
- `hang`: the checker does not finish within 60 seconds

At most 200 witnesses are read from one report.

## Requirements on the report

Your tester is run against several Go-native builds that are not installed here, each one from
before some upstream fix. Every program you report is re-checked independently under 6.0.3, under
that build, and under a later build that carries the fix. A bug is established when one of your
programs splits 6.0.3 and the earlier build and agrees with 6.0.3 on the later one.

Five requirements apply, and all five must hold together — satisfying four of them well does not
compensate for failing the fifth.

- Accuracy. Every witness must reproduce. If a re-check does not observe the outcomes you recorded
  for it, the whole report is void, however many real bugs it also contains. Verify every witness
  before you write it out.
- Coverage. Report a witness for as many of the present bugs as you can.
- Restraint. Per toolchain, three witnesses per distinct `mechanism` label that really do split the
  two checkers there are expected, counting at most eight labels. Beyond that the report is treated
  as proportionally diluted. Programs that do not split consume the allowance and contribute
  nothing.
- Discrimination. A bug is distinguished only when all the witnesses establishing it share one
  label, and no other bug carries that same label. The vocabulary is yours; telling the bugs apart
  is the point.
- Economy. A witness counts as minimal only if its source is at most 1500 bytes.

Not every divergence is a bug of this kind. Some differences between 6.0.3 and the port are present
on every Go build and were never fixed; those contribute nothing.

## What is here

- `/opt/ts/tsc6/bin/tsc`, the baseline checker
- `/opt/ts/dev/bin/tsc`, a recent Go-native build that carries none of the bugs you are looking for:
  it is for developing and checking your tester, not for finding bugs
- `/opt/ts/practice/bin/tsc`, an older Go-native build, also newer than every bug you are looking
  for, that still carries a few divergences fixed before `dev`: a program that splits 6.0.3 from
  `practice` and agrees with 6.0.3 on `dev` is the shape of a witness that counts, so you can check
  your tester end to end
- `/app/docs/`, notes on the toolchain layout and on where a port of the checker can drift
- Node 22 and Python 3, both also present wherever your tester runs
- no network, no TypeScript or typescript-go source tree, and no checker test suite

## What is hard about this

The two checkers agree on almost every program. They disagree where the port re-implements
something subtle in the original. A generator
that emits programs without building such structures deliberately will check a great many programs
and find nothing.
