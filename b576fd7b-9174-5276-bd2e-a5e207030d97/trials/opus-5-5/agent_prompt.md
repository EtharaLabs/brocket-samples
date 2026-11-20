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

# Find conformance divergences between TypeScript's two type checkers

Build a differential testing TOOL in TypeScript at `/app/tester/`:

```
/app/tester/run --toolchain <name> --budget <seconds> --seed <n> --out <file>
```

The JavaScript checker is fixed at TypeScript 6.0.3. The native Go checker is a
supplied TypeScript 7 toolchain. Both are installed as the `typescript` npm package.
Their executables are respectively:

```
/opt/compilers/reference/node_modules/.bin/tsc
/opt/compilers/<name>/node_modules/.bin/tsc
```

Do not assume `<name>` is `dev`; it names a build you have not seen. Do not branch
on versions, maintain a version-to-input table, inspect the compiler installation
for builds you were not handed, or hardcode version-specific behavior: a tool that
does any of these is rejected outright. The same seed must yield the same report.
Generate structures and measure them on the supplied checker; do not guess
outcomes. The budget is wall-clock seconds (normally 300). Exceeding it by more
than ten percent terminates the invocation, and only a report already on disk
survives.

## Comparison protocol

Every candidate is a self-contained single `.ts` file, with no external dependencies.
Write it as `p.ts` in an otherwise empty scratch directory. Run BOTH checkers with
exactly these options, and no others:

```
--noEmit --strict --target es2022 --module esnext --moduleResolution bundler --lib es2022 --pretty false
```

Do not emit or check JavaScript or declarations. No tsconfig, additional source files,
ambient external libraries, filesystem-dependent imports, plugins, or option changes.
Use a 60-second timeout per checker and SIGKILL on expiry. Set `GOMAXPROCS=2`.
The compiler packages supply their normal standard libraries.

Outcomes are **classes**, not diagnostic text or error counts:

* `accept`: exit status 0.
* `reject`: exit status 1 or 2 AND at least one compiler diagnostic (`error TS<number>:`).
* `crash`: any other termination, including a signal or nonzero status without diagnostics.
* `timeout`: the process has not completed after 60 seconds.

Compare only these classes. Different diagnostic wording, positions, codes or order
within `reject` do NOT constitute a finding. A toolchain that cannot be executed is
an infrastructure error, not a compiler crash to report.

Write one JSON object to `--out`:

```json
{"witnesses":[{"id":"stable-id","source":"complete TypeScript program","reference":"accept","native":"reject","mechanism":"your structural explanation label"}]}
```

`reference` and `native` must be one of the four classes above. IDs must be unique
and nonempty. Labels must be nonempty. Reports may contain at most 2 MiB; witnesses
at most 64 KiB each. Only the first 200 witnesses are read. A witness that breaks the
schema, repeats an id, carries an empty label, or exceeds its size is dropped on its
own and still consumes the witness allowance; it does not discard your other
witnesses. A report that is not JSON, carries no `witnesses` array, or exceeds 2 MiB
is unreadable, and an unreadable report is rejected whole.

Your invocation runs as uid and gid 65534 with the working directory
`/app/tester`, which you own. Write scratch files under the system temporary
directory rather than relative to the program, and expect `HOME` to be a directory
outside your submitted tree. Write the report to `--out` as soon as its contents are
settled, so that an interrupted invocation still leaves one on disk, and exit zero
within the budget regardless.

## What counts as a porting bug

A difference matters only when it is a regression that was later corrected: the
program must split on the build under test and agree on the build carrying the
correction. A difference that persists across every build is intentional or
inherent, and is not a finding. TypeScript 7 deliberately changed some semantics
and removed options; even under the pinned options, not every split is a porting
bug.

Report only classes your tool measured by running the two checkers. Never infer,
assume, or fill in a class you did not observe, and report a witness only once its
two classes reproduce on a repeated measurement. A class that moves between repeated
measurements is not a finding.

## Requirements

* Represent the regression corrected in the build under test with at least one
  witness that splits on that build and agrees once corrected.
* Report at most three witnesses in total, counting any witness you emit that breaks
  the schema. They need not concern one bug.
* Give each distinct bug exactly one mechanism label, and never reuse a label for a
  different bug. The tool is invoked separately for each build under test, so a label
  must be a deterministic function of the structure it describes — identical, up to
  case and whitespace, whenever that structure recurs, and never derived from
  discovery order. Choose your own vocabulary; distinguishing mechanisms is the task.
* Reduce each witness to at most 3200 UTF-8 bytes. A larger witness is still a valid
  witness, so never suppress one for its size alone.
* Exit zero inside the budget on every invocation.

Reporting every difference you observe is not the safe alternative: background noise
spends the three-witness limit on findings you have not established. An empty
`witnesses` array is a valid report.

## What is installed

There is exactly ONE native development checker, named `dev`, which carries every
correction, plus the fixed reference. No build you will be asked about is installed
here. The development checker is for implementing and self-checking the tool, and it
is a build carrying corrections that a genuine regression must agree on; it is not
an inventory of the bugs. A useful generator must deliberately compose type
relationships; independent syntactic sampling mostly produces agreements or noise.

Node 26.13.0 runs `.mts` directly using native type stripping. Your executable `run`
can be a JavaScript-subset TypeScript entry point importing an `.mts` module; make
it executable. `/app/docs/` carries neutral background documentation and a license.
There is no network, upstream source tree, issue corpus, or upstream test suite.
Only `/app/tester/` is collected, and it must run offline. Treat both compiler
installations as read-only: do not modify, patch, or reinstall either one.
