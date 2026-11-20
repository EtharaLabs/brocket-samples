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
outside your submitted tree. A report is read if it exists on disk, whatever status
your process exits with, but a non-zero exit or a budget overrun counts against the
tool on its own, so exit cleanly.

## What counts as a porting bug

A difference matters only when it is a regression that was later corrected: the
program must split on the build under test and agree on the build carrying the
correction. A difference that persists across every build is intentional or
inherent, and is not a finding. TypeScript 7 deliberately changed some semantics
and removed options; even under the pinned options, not every split is a porting
bug.

Every witness you report is independently re-measured on the fixed reference and on
the named build. Claim only classes you measured: one witness whose two classes do
not reproduce invalidates the whole report, not merely its own row. Timing is not
held against you — a class that moves between repeated measurements is recorded as
unstable and charged to nobody, and a failure of the compiler installation itself
is an infrastructure fault, which is reported as such and the run repeated.

A report is accepted when the tool exists and is executable, the invocation
launches, the JSON parses within its size bound, no version-specific literal
appears in the tool, and every witness reproduces.

## What makes a report good

An accepted report is then weighed on five qualities together, and abandoning any
one of them is not repaired by the other four:

* **Coverage**: the regression corrected in the build under test is represented by
  at least one witness that splits on that build and agrees once corrected.
* **Restraint**: a report carries at most three witnesses in total. Three are free;
  past that, restraint falls as `3 / reported`, counting witnesses you emit that
  break the schema as well as sound ones. They need not concern one bug — a witness
  aimed at a regression this build does not carry simply earns nothing.
* **Discrimination**: each distinct bug carries exactly one mechanism label, and no
  two bugs share a label. The tool is invoked separately for each build under test,
  and labels are compared across those invocations, normalized for case and
  whitespace — so a label must be a deterministic function of the structure it
  describes, never of discovery order. Choose your own vocabulary; distinguishing
  mechanisms is the task.
* **Economy**: a witness of at most 3200 UTF-8 bytes is minimal. Larger witnesses
  are accepted, but are not minimal.
* **Cleanliness**: every invocation exits zero inside its budget.

An honest empty report is accepted and establishes nothing. Reporting every
difference you observe is not the safe alternative: background noise spends the
three-witness allowance and destroys discrimination.

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
Only `/app/tester/` is collected, and it must run offline. Do not modify the
compiler installation: the copies it is re-measured against are immutable.
