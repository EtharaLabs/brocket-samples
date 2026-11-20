# Oracle provenance

This is the frozen reference solution for `brocket/3e527b39-1359-490f-a563-828173c1df53`. It is a Zig implementation of git v2.56.1 that FORGE did not hand-author, produced by a coding agent under this contract's own red lines, with git's own test suite as its feedback signal through an honest grader.

## Identity

| Field | Value |
| --- | --- |
| Frozen digest, solution tree | `735bf63985740200cf84dc398cabab8b712f393a22eba74841abeaa32ccde9c6` |
| Frozen digest, graded manifest | `0487b019285d49345aa1bd47fb1f02861f31fb93a5f9e939d0db1ab4b68f16d7` |
| Source | 15 files, 2,902 lines of Zig across ten modules plus `build.zig` |
| Toolchain | Zig 0.17.1, pinned by the bundle's own `environment/Dockerfile` |
| Frozen at | 2026-11-13T02:40:00Z |

The digest over the solution tree is the SHA-256 of the sorted per-file SHA-256 list, taken over the tree with `.zig-cache` and `zig-out` excluded, which are build artifacts rather than source.

## Producing harness

The producer was a coding-agent subagent of this FORGE run, dispatched through the run's own orchestration under the `deep-low` category, which routes backend, logic and algorithm work. Six passes ran in total: one 12-minute feasibility probe and five development passes. Passes one through three ran in a single agent session which the orchestrator reaped after three and a half hours; passes four and five each began as a fresh agent and resumed from the handover the previous agent maintained at `PROGRESS.md`.

The agent's feedback signal was an honest grader invoking this bundle's own verifier image, so every score it saw came from git's genuine C-built `test-tool`, its built `templates/blt`, and the frozen case manifest, rather than from any harness the agent could influence. The agent was forbidden from editing the grader or the manifest.

**The underlying model identity is not recorded here, because this instrument cannot observe it.** The orchestration exposes a category rather than a model name, so naming one would be a guess. A reader who needs the model must obtain it from the orchestration records of run `forge-piyushagrawal-grt-20261110t213655z-55a133`, where the dispatches appear as background tasks `bg_a399e6b4`, `bg_33a78f74`, `bg_2ef34258` and `bg_8d203378`. This is recorded as a gap rather than filled with an assumption.

## Budget

| Measure | Value |
| --- | --- |
| Agent wall-clock | 334 minutes, 5h 34m, across six passes |
| Pass durations | 12m probe, then 66m, 55m, 90m, 67m, 44m |
| Declared agent budget for the task | unset, because no `requirements/` grant binds one |

The contract requires the oracle's budget to sit far above the task's declared budget. That comparison cannot be completed while the task's own budget is ungranted, so it is recorded as unverified rather than claimed. The absolute figure above stands on its own.

## What it reaches, measured

Scored against the frozen graded manifest of 10,149 cases and 32,574 weight:

| Submission | Score | Weight |
| --- | ---: | ---: |
| this oracle | 1.000000 | 32,574 of 32,574 |
| the bundle's shipped scaffold, a no-op that compiles | 0.000000 | 0 of 32,574 |
| a 12-minute unguided agent attempt | 0.263370 | 8,579 of 32,574 |

The oracle scores exactly 1.0 by construction, since `oracle_policy.reaches_one` defines a case as graded only when the oracle passes it. That is a definition rather than an achievement, and the figure carries no information about difficulty on its own. The no-op and throwaway figures are the ones that bound the reward scale, and both were measured against this same manifest rather than against the full suite.

Against the full 849-script reference-passing set of 85,646 weight, from which the manifest was selected, the oracle earns 32,574, which is 0.380333. Its progression across the six passes was 0.108341, 0.184632, 0.280153, 0.338638, 0.373094, 0.380333. Every one of those figures was re-measured by this instrument on a frozen snapshot and matched the producing agent's own claim to the digit.

## Selection

The graded set is `O and R minus N`. `R` is the reference's own pass set, measured on both declared platforms with identical counts, 33,503 cases and 335 failures over the same 60 scripts on each. `N` is provably empty: `t/test-lib.sh` calls `git version` at line 170, `git --exec-path` at line 1432 and `git init` at line 1619 before the first TAP line, so a binary answering none of them emits nothing to parse and can pass no case. `O` is this oracle's pass set, captured by replaying all 849 graded scripts through the grader's own `suite` module as the grader's own user, so pass semantics are identical to scoring by construction rather than by re-implementation.

That selection was taken twice. A first attempt hand-rolled the TAP parsing and ran as root; it reported 35,791 weight, which disagreed with the oracle's independently graded 32,574 by 3,217. The cause was the attempt counting `ok N # skip` lines as passes, which scoring correctly excludes, and running as a user whose permissions differ from the grader's. The second attempt, through the grader's own module and user, reported 32,574, matching the independent grade exactly. Only the second is used.

## Red lines, audited every pass

The implementation is Zig throughout. Each pass was audited over the whole source for `std.process.Child`, `ChildProcess`, `execv`, `posix_spawn`, `system(`, `/usr/bin/git`, `/opt/git` and `translate-c`, and every count was zero at every pass. No non-Zig source file and no prebuilt object ever appeared in the tree. Nothing under the audited parent repository was modified by any pass, confirmed by checking that no tracked file there carried an mtime inside any run window.

The producing agent also declined, unprompted, to fake a commit-graph in order to harvest the 1,256 weight of `t4216-log-bloom.sh`, recording that trace-only shortcuts "would not be legitimate". It reported its own CRLF regression against itself in an earlier pass and repaired it in the next, and it refused to attribute a score to a grading attempt that had failed.

## Known limitations of the reference

These bound what the task can ask of a solver, because a case the oracle does not pass is not graded.

The SHA-256 object format is absent, so `t1016-compatObjectFormat.sh` contributes nothing. Network transports are absent: clone and fetch work in-process over local paths and file URLs only, with no negotiation, no shallow clone, no promisor fetching, and no `receive-pack` or `upload-pack` over a wire. Real commit-graph storage with Bloom filters is absent. Merge support handles fast-forward and three-way file-entry cases and rejects conflicting content rather than resolving it. Incremental multi-pack-index chains, git's exact bitmap commit-selection heuristics, colored and moved-code diffs, and much of the revision formatting surface are absent.

The producing agent's own recommendation after the sixth pass was to stop open-ended development, on the grounds that the remaining large families need whole subsystems rather than gap-filling. Per-hour yield across the passes fell 0.069, 0.105, 0.039, 0.031, 0.010, which supports that reading.
