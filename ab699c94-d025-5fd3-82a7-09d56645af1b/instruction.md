# A differential tester for rustc's two trait solvers

rustc carries two trait solvers. The original one still runs on stable and beta. The
next-generation solver is the nightly default and is being stabilized to replace it. Both are
reachable from any nightly compiler by flag:

    rustc -Znext-solver=no         the old solver
    rustc -Znext-solver=globally   the next-generation solver

A program that one solver accepts and the other rejects is, with few exceptions, a bug in one of
them. Upstream fixes such disagreements continuously, and each fix is a program that used to split
the two solvers and no longer does.

Build the tool that finds them.

## What to build

A differential tester at `/app/tester/` that, given one toolchain, generates Rust programs,
compiles each under both solvers, and reports the programs on which they disagree.

It must be executable as:

    /app/tester/run --toolchain <name> --budget <seconds> --seed <n> --out <file>

`--toolchain` is a rustup toolchain name, passed to `rustc` as `+<name>`. Your tester must not
assume it is the toolchain installed here: it will be run against several others. `--budget` is the
wall-clock second count your run may take; exceeding it by more than 10 percent is a failed run.
`--seed` fixes your generator's randomness, and the same seed must produce the same report.
`--out` is where you write the report.

## The report

`--out` receives one JSON object:

    {
      "witnesses": [
        {
          "id": "<your own stable identifier>",
          "source": "<the complete Rust program, as one string>",
          "edition": "2015" | "2018" | "2021" | "2024",
          "old": "accept" | "reject" | "ice" | "hang",
          "next": "accept" | "reject" | "ice" | "hang",
          "mechanism": "<your label for what this exercises; see the criteria below>"
        }
      ]
    }

`old` is the outcome under `-Znext-solver=no` and `next` the outcome under
`-Znext-solver=globally`, where the outcome classes are:

- `accept`: the compiler exits 0
- `reject`: the compiler exits 1
- `ice`: the compiler exits 101, an internal compiler error, or fails in any other way that is not
  a rejection of your program, such as dying on a signal
- `hang`: the compiler does not finish inside your own per-program timeout

Every program you report must compile as a library crate with no external dependencies, under the
edition you name, within 60 seconds. Only the first 200 witnesses in a report are read, and no
more than three per toolchain are wanted, so a short report of witnesses you would defend is worth
far more than a long one.

## What the review will check

Your tester will be run against several rustc toolchains that are not installed here, each one a
nightly from before some upstream fix. For each of them we run your tester, then recompile each
program you reported ourselves, under both solvers, on that toolchain and on a later nightly that
carries the fix. A program accounts for a bug when it splits the two solvers on the earlier
toolchain and stops splitting on the later one.

Four things are asked of the report. Each is a condition on the whole of it, so falling short on
one is not made up by doing well on the others.

- Account for as many of the bugs behind those toolchains as you can.
- Report at most three witnesses per toolchain. Past three, the extras are discounted in
  proportion: thirty witnesses where three would do leave a tenth of the report standing. Report
  what you would defend, not everything you observed.
- Give every witness a `mechanism` label of your own choosing. A bug is told apart only when all
  the witnesses that account for it share one label, and no other bug in your report carries that
  same label. The vocabulary is yours; telling the bugs apart is the point.
- Keep each reported program to at most 1500 bytes of source.

Two consequences are worth stating plainly.

Reporting a disagreement you cannot stand behind invalidates the whole report. If one of your
witnesses is recompiled and does not show the disagreement you recorded for it, the report is
discarded, however many real bugs are also in it. Verify every witness before you report it.

Not every disagreement is a bug. The two solvers differ by design in places, and some differences
are present on every compiler and were never fixed. Those account for nothing, and the
three-per-toolchain limit means they crowd out the ones that do: a tester that reports every split
it sees is near worthless however many real bugs are buried in the pile.

## What is here

- the toolchain `dev`, a recent nightly with both solvers, which carries none of the bugs you are
  looking for: it is for developing and checking your tester, not for finding bugs
- `/app/docs/`, the rustc-dev-guide chapters on the next-generation solver
- no network, no rustc source tree, and no rustc test suite

## What is hard about this

The solvers agree on almost every program. They disagree where the trait system does something
structurally interesting. A generator that emits trait programs without building such structures
deliberately will compile a great many programs and find nothing but the differences that are
present everywhere.
