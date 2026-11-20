# typescript-checker-differential

The agent builds a differential testing tool that finds where TypeScript's two type checkers disagree. The full directive the agent receives is [instruction.md](instruction.md).

The tool it must deliver takes a toolchain name, a wall-clock budget, a seed, and an output path, generates self-contained single-file TypeScript programs, runs both the frozen reference checker and the named native checker over each one under one frozen option set, classifies each run as `accept`, `reject`, `crash`, or `timeout`, and reports only the programs whose two classes differ. The toolchain name at grading time names a build the agent has never seen, so no version table and no version branch can produce a report.

## Environment

Base image `node:26.13.0-bookworm-slim` pinned by digest, two CPUs, 6144 MiB, 12288 MiB storage, `GOMAXPROCS=2`, no network in either phase, agent timeout 43200 s. The image installs two checkers and nothing else: the frozen reference `typescript@6.0.3` at `/opt/compilers/reference` and one public development build `typescript@7.1.0-dev.20261113.1` at `/opt/compilers/dev`. Neutral background documentation sits at `/app/docs`. The submitted surface is `/app/tester`, owned by the non-root `node` user. No graded build is installed here.

## Verifier

A separate verifier environment, offline, whose `tests/` tree is the image build context and whose `/tests` is root-owned at mode 0700. It installs the eleven graded builds that the agent image does not carry. For each hidden correction window the grader launches the submitted entry point as uid 65534 against the pre-correction build, then recomputes every reported witness itself on the frozen reference and on both the pre-correction and post-correction builds. A window is caught only when a witness disagrees before the correction and agrees after it.

Reward is continuous in [0, 1] and written to `/logs/verifier/reward.json`:

| Factor | What it measures |
| --- | --- |
| `validity_gate` | the tester launched, the report parsed, and every witness reproduced |
| `recall` | the fraction of hidden windows caught |
| `precision` | three free witnesses per window, then `3 / reported` |
| `attribution` | the fraction of caught windows whose crediting witnesses share exactly one label unused by any other window |
| `minimality` | the fraction of crediting witnesses at most 3200 UTF-8 bytes |
| `completion` | the fraction of invocations that exited zero inside their budget |

All six multiply — `reward = validity_gate * recall * precision * attribution * minimality * completion` — so a fabricated or unreproducible witness zeroes the whole submission, and reporting every difference earns a gate pass and nothing else. The grader also prints the `>>>>> Start Structured Result` block that the `structured_json` parser declared in `task.toml` reads.

## Layout

```tree
<uuid>/
├── instruction.md              # the only agent-visible statement
├── task.toml                   # schema 1.4, bounded_continuous reward, dual-platform matrix
├── README.md                   # this page
├── environment/
│   ├── Dockerfile              # multi-stage, digest-pinned, non-root final stage
│   ├── .dockerignore           # deny-by-default build context
│   └── docs/                   # neutral background documentation and its licences
├── solution/                   # private: never in the agent image
│   ├── solve.sh                # the oracle entry point
│   ├── tester/                 # the reference tool: generator, executor, classifier, selection
│   └── TRUTH.md                # the measured ground truth every claim resolves to
└── tests/                      # private: the verifier image build context
    ├── Dockerfile              # installs the eleven graded builds
    ├── test.sh                 # the verifier entry point
    ├── grader/                 # grade.mts, check.mts, windows.json, impossible-window.json
    └── controls/               # the author-side control programs the matrix runs
```

## Running

```sh
harbor run -p drafts/<uuid> -a oracle -n 1 \
  --override-cpus 2 --override-memory-mb 6144
harbor run -p drafts/<uuid> -a nop -n 1 \
  --override-cpus 2 --override-memory-mb 6144
```

These bytes have now been measured. On `linux/arm64` the oracle returns reward 1.0 with `validity_gate` 1, 6 of 6 windows caught, 15 witnesses read and 0 fabricated, unstable or unreproducible; the no-op returns reward 0.0 with `validity_gate` 0. Both runs completed with zero trial errors. That closes the re-measurement this page previously owed for solvability and for the null floor, and nothing else. The nine-mode control matrix runs inside the verifier image with `node /tests/controls/matrix.mts`, writing its evidence to a mounted `/evidence`; the authoring run keeps that evidence in the workbench at `.seed/tasks/<uuid>/controls/`, never in the bundle.

The directory name is the uuid the authoring run minted from these bytes, so it is deliberately not written here: naming it inside a hashed byte would make the name depend on itself.

## What you would change

To move the difficulty, change the generator's structural families in `solution/tester/generate.mts` and the window set in `tests/grader/windows.json`; both must move together, because every window needs a reachable witness family. To change the scoring shape, change `tests/grader/grade.mts` and the `reward` block of the run contract together. The byte cap of 3200 in `grade.mts` is calibrated against the largest credited family, a pair of at least 34 array-linked interfaces.

Difficulty here is unmeasured. No external signed pilot exists for these bytes, so the disposition caps at `HOLD:PILOT_REQUIRED` and no number on this page is difficulty evidence.

The measured oracle and no-op above do not lift that cap, and they are not offered as if they did. An oracle pass shows the reference solution solves the task and that the grader separates it from an untouched environment; difficulty is a statement about agents, which neither run observes.

The four arm64 control modes are no longer owed. The full nine-mode matrix has been run inside the verifier image on native `linux/arm64` under the declared 2 CPU / 6144 MiB envelope: `empty` 0.0 with gate 1, `impossible` 0.0 with gate 1 and 0 of 1, `mode-discipline` 0.0 with gate 1, and `one-mechanism` 0.1667 with gate 1 and 1 of 6 caught at attribution and minimality 1.0, alongside `oracle` 1.0, `missing` 0.0, and `naive`, `spray` and `liar` all 0.0. Every control sits below the oracle, and `one-mechanism` shows the reward paying continuous partial credit rather than collapsing to zero.

**One item now stands between this bundle and a release: a signed external pilot against a frontier cohort.** Lifting the hold requires the pilot, not another oracle run and not the control matrix.
