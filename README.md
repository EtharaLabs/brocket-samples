<p align="center"><img src="images/hero.svg" alt="brocket" width="720"></p>

# Brocket EdgeBench: samples

<p align="center"><b>Five sample bundles from brocket, a Harbor benchmark of adversarial compiler and toolchain tasks graded by deterministic offline verifiers.</b></p>
<p align="center"><b>Five sample bundles from brocket, a Harbor benchmark of adversarial compiler and toolchain tasks graded by deterministic offline verifiers.</b></p>

<p align="center"><a href="#summary"><img src="https://img.shields.io/badge/bundles-5-845EF7" alt="bundles: 5"></a> <a href="#summary"><img src="https://img.shields.io/badge/harbor_schema-1.4-845EF7" alt="harbor schema: 1.4"></a> <a href="#trials"><img src="https://img.shields.io/badge/mean_reward-0.3860-845EF7" alt="mean reward: 0.3860"></a> <a href="#trials"><img src="https://img.shields.io/badge/pass%401-0_of_5-845EF7" alt="pass@1: 0 of 5"></a></p>
<p align="center"><a href="#summary"><img src="https://img.shields.io/badge/bundles-5-845EF7" alt="bundles: 5"></a> <a href="#summary"><img src="https://img.shields.io/badge/harbor_schema-1.4-845EF7" alt="harbor schema: 1.4"></a> <a href="#trials"><img src="https://img.shields.io/badge/mean_reward-0.3860-845EF7" alt="mean reward: 0.3860"></a> <a href="#trials"><img src="https://img.shields.io/badge/pass%401-0_of_5-845EF7" alt="pass@1: 0 of 5"></a></p>

<p align="center"><sub><a href="#abstract">Abstract</a> | <a href="#summary">Summary</a> | <a href="#tasks">Tasks</a> | <a href="#trials">Trials</a> | <a href="#coverage">Coverage</a> | <a href="#dataset-structure">Dataset structure</a> | <a href="#reproduction">Reproduction</a> | <a href="#verification-and-quality-assurance">Verification and quality assurance</a> | <a href="#cite">Cite</a> | <a href="#license">License</a> | <a href="#contact">Contact</a></sub></p>
<p align="center"><sub><a href="#abstract">Abstract</a> | <a href="#summary">Summary</a> | <a href="#tasks">Tasks</a> | <a href="#trials">Trials</a> | <a href="#coverage">Coverage</a> | <a href="#dataset-structure">Dataset structure</a> | <a href="#reproduction">Reproduction</a> | <a href="#verification-and-quality-assurance">Verification and quality assurance</a> | <a href="#cite">Cite</a> | <a href="#license">License</a> | <a href="#contact">Contact</a></sub></p>

## Abstract

Brocket is a benchmark of adversarial terminal tasks in [Harbor](https://github.com/laude-institute/harbor) format, built at the compiler and toolchain layer. It targets [EdgeBench](https://arxiv.org/abs/2607.05155) (arXiv:2607.05155), aiming at capabilities that benchmark measures but does not saturate: a twelve-hour horizon against a real upstream codebase, a continuous reward, a floor measured at zero, and a frontier pilot that lands far below one.

Every bundle gives the agent 12 hours with no network and is scored by a deterministic verifier that runs in a separate container built from the bundle's own `tests/` tree. No bundle calls an LLM judge and neither phase reaches the network, so a reward is a property of the submitted artifact rather than of a judge, and the score is reproducible from the committed bytes. Reward is continuous from 0 to 1 as a product of gated factors: each bundle's reference solution is measured at exactly 1.0 and its null floor at exactly 0.0. The gated product means partial credit tracks real mechanism coverage instead of volume, so reporting every difference, or one unreproducible witness, pays exactly zero.

This repository holds the five-bundle sample: a clean-room reimplementation of git v2.56.1 in Zig graded on git's own test suite, a semantics-preserving MIR optimizer extension in rust-lang/rust, and three differential testers for rustc's two trait solvers and TypeScript's two checkers. Each bundle is one Harbor task in a directory named by its content-derived uuid5, so the name doubles as an integrity check. Pilot rollouts from a 12-hour `claude-opus-5-5` run ship with each bundle under `trials/opus-5-5/`.
This repository holds the five-bundle sample: a clean-room reimplementation of git v2.56.1 in Zig graded on git's own test suite, a semantics-preserving MIR optimizer extension in rust-lang/rust, and three differential testers for rustc's two trait solvers and TypeScript's two checkers. Each bundle is one Harbor task in a directory named by its content-derived uuid5, so the name doubles as an integrity check. Pilot rollouts from a 12-hour `claude-opus-5-5` run ship with each bundle under `trials/opus-5-5/`.

## Summary

| Property | Value |
| --- | --- |
| Bundles | 5 |
| Domain | Software engineering (compiler and toolchain layer) |
| Systems under test | git, rust-lang/rust, microsoft/typescript-go |
| Deliverable languages | Zig, Rust, TypeScript (one tester is language-free, its oracle is Python) |
| Format | Harbor task, schema 1.4, `harbor_release` 0.24.0 |
| Reward type | `bounded_continuous`, 0 to 1 |
| Platforms | linux/amd64, linux/arm64 |
| Agent budget | 43,200 s (12 hours), `no-network` |
| Verifier | `environment_mode = "separate"`, `no-network`, no LLM judge |
| Average handling time (AHT) | 2,400 minutes per task |
| Agent | Claude Code with `claude-opus-5-5` |
| Runs per bundle | 1 |
| Null floor, measured | 0.0 on every bundle |
| Reference solution, measured | 1.0 on every bundle |
| Mean best reward | 0.3860 |
| pass@1 at reward 1.0 | 0 of 5 |

## Tasks

| Bundle | System under test | Language | Objective | `task_id` |
| --- | --- | --- | --- | --- |
| [`3e527b39`](3e527b39-1359-490f-a563-828173c1df53/) | git v2.56.1 | Zig | Reimplement git as a drop-in replacement in a clean room, graded on git's own test suite over a frozen manifest of 10,149 cases and 32,574 weight. The verifier rebuilds the binary from the submitted Zig source in a stage holding no readable git. | `git_v2561_zig_dropin` |
| [`8fc1b9be`](8fc1b9be-68ab-5f53-b369-3fb4bc621933/) | rust-lang/rust 1.99.1 | Rust | Extend the MIR optimizer so it removes every provably-always-true slice or array bounds check and never one that can fail. Mechanism-class-weighted score, multiplied by a soundness gate and a regression gate. | `rustc_mir_bounds_check_elision` |
| [`ab699c94`](ab699c94-d025-5fd3-82a7-09d56645af1b/) | rustc old and next-generation trait solvers | any (oracle in Python) | Build a differential tester between the two trait solvers, graded against thirteen pinned nightlies bracketing seven merged upstream fixes across five mechanisms. | `rustc_trait_solver_differential` |
| [`b576fd7b`](b576fd7b-9174-5276-bd2e-a5e207030d97/) | TypeScript JavaScript and native checkers | TypeScript | Build a structural conformance differential tester between the two checkers. Reward is the product of validity gate, recall, precision, attribution, minimality, and completion over six correction windows. | `typescript_checker_differential` |
| [`d49e93a6`](d49e93a6-c4d2-5013-ab29-99fbe0cc3089/) | TypeScript 6 checker and Go-native TypeScript 7 checker | TypeScript | Build a differential tester graded against fourteen dated published Go builds bracketing seven merged upstream fixes across seven distinct mechanisms. | `ts_checker_differential` |

## Trials

Each bundle was run once with Claude Code and `claude-opus-5-5` at the declared 43,200 s agent budget and scored by the bundle's own deterministic verifier. Every run exhausted its 12-hour budget. Trials are stored in each bundle's `trials/opus-5-5/`.

Reward is the maximum over every retained `submissions/<round>/report.json`, which is the verifier's own output, rather than the harness summary file. All 484 retained reports were scanned and none reached 1.0.

| Bundle | Best reward | Graded outcome | First round at best | Rounds<br/>agent / auto | Retained<br/>reports | Agent<br/>wall clock |
| --- | ---: | --- | --- | ---: | ---: | ---: |
| [`3e527b39-1359-490f-a563-828173c1df53`](3e527b39-1359-490f-a563-828173c1df53/trials/opus-5-5/) | 0.6107 | weighted score over the frozen 10,149-case manifest | `auto-47` | 15 / 47 | 62 | 12h 0m |
| [`8fc1b9be-68ab-5f53-b369-3fb4bc621933`](8fc1b9be-68ab-5f53-b369-3fb4bc621933/trials/opus-5-5/) | 0.4384 | 83 of 99 held-out always-safe checks removed, both gates 1.0 | `agent-62` | 64 / 42 | 106 | 12h 0m |
| [`ab699c94-d025-5fd3-82a7-09d56645af1b`](ab699c94-d025-5fd3-82a7-09d56645af1b/trials/opus-5-5/) | 0.2857 | 2 of 7 correction windows | `agent-3` | 22 / 47 | 69 | 12h 0m |
| [`b576fd7b-9174-5276-bd2e-a5e207030d97`](b576fd7b-9174-5276-bd2e-a5e207030d97/trials/opus-5-5/) | 0.1667 | 1 of 6 correction windows, precision and attribution 1.0 | `agent-3` | 23 / 29 | 48 | 12h 0m |
| [`d49e93a6-c4d2-5013-ab29-99fbe0cc3089`](d49e93a6-c4d2-5013-ab29-99fbe0cc3089/trials/opus-5-5/) | 0.4286 | 3 of 7 correction windows (W4, W5, W6) | `agent-56` | 56 / 143 | 199 | 12h 0m |
| **mean** | **0.3860** | **0 of 5 reached 1.0** | — | **36 / 62** | **97** | **12h 0m** |

Two figures in the harness summary files are not the headline and should not be read as one. `best_pass_rate` is not comparable across bundles: three of the five graders report `total_tests` 0 and leave it at 0.0 while scoring above zero, and on the one bundle where both are real they diverge, because removing 83 of 99 checks pays 0.4384. And on the dated-builds TypeScript bundle, `final_result.json` carries a stale `best_score` of 0.2857: that run was killed by the 12-hour wall clock and missed its own last two rounds, `agent-56` and `auto-143`, which both scored 0.428571 with `valid` true and verifier exit 0.

Each trial folder is the harness run output:

| Path | Contents |
| --- | --- |
| `final_result.json` | Agent, model, best score and round, round counts, runtime, timeout flag |
| `run_history.json` | Per-round history for the run |
| `agent_prompt.md` | Prompt the agent was given |
| `agent_output.txt` | Agent transcript (git-lfs) |
| `submissions/<round>/report.json` | The verifier's own output: score, validity, metrics, per-check details |
| `submissions/<round>/` | Also `test_output.txt`, `eval.sh`, `run_instance.log`, and `submission.tar.gz` |
| Bundles | 5 |
| Domain | Software engineering (compiler and toolchain layer) |
| Systems under test | git, rust-lang/rust, microsoft/typescript-go |
| Deliverable languages | Zig, Rust, TypeScript (one tester is language-free, its oracle is Python) |
| Format | Harbor task, schema 1.4, `harbor_release` 0.24.0 |
| Reward type | `bounded_continuous`, 0 to 1 |
| Platforms | linux/amd64, linux/arm64 |
| Agent budget | 43,200 s (12 hours), `no-network` |
| Verifier | `environment_mode = "separate"`, `no-network`, no LLM judge |
| Average handling time (AHT) | 2,400 minutes per task |
| Agent | Claude Code with `claude-opus-5-5` |
| Runs per bundle | 1 |
| Null floor, measured | 0.0 on every bundle |
| Reference solution, measured | 1.0 on every bundle |
| Mean best reward | 0.3860 |
| pass@1 at reward 1.0 | 0 of 5 |

## Tasks

| Bundle | System under test | Language | Objective | `task_id` |
| --- | --- | --- | --- | --- |
| [`3e527b39`](3e527b39-1359-490f-a563-828173c1df53/) | git v2.56.1 | Zig | Reimplement git as a drop-in replacement in a clean room, graded on git's own test suite over a frozen manifest of 10,149 cases and 32,574 weight. The verifier rebuilds the binary from the submitted Zig source in a stage holding no readable git. | `git_v2561_zig_dropin` |
| [`8fc1b9be`](8fc1b9be-68ab-5f53-b369-3fb4bc621933/) | rust-lang/rust 1.99.1 | Rust | Extend the MIR optimizer so it removes every provably-always-true slice or array bounds check and never one that can fail. Mechanism-class-weighted score, multiplied by a soundness gate and a regression gate. | `rustc_mir_bounds_check_elision` |
| [`ab699c94`](ab699c94-d025-5fd3-82a7-09d56645af1b/) | rustc old and next-generation trait solvers | any (oracle in Python) | Build a differential tester between the two trait solvers, graded against thirteen pinned nightlies bracketing seven merged upstream fixes across five mechanisms. | `rustc_trait_solver_differential` |
| [`b576fd7b`](b576fd7b-9174-5276-bd2e-a5e207030d97/) | TypeScript JavaScript and native checkers | TypeScript | Build a structural conformance differential tester between the two checkers. Reward is the product of validity gate, recall, precision, attribution, minimality, and completion over six correction windows. | `typescript_checker_differential` |
| [`d49e93a6`](d49e93a6-c4d2-5013-ab29-99fbe0cc3089/) | TypeScript 6 checker and Go-native TypeScript 7 checker | TypeScript | Build a differential tester graded against fourteen dated published Go builds bracketing seven merged upstream fixes across seven distinct mechanisms. | `ts_checker_differential` |

## Trials

Each bundle was run once with Claude Code and `claude-opus-5-5` at the declared 43,200 s agent budget and scored by the bundle's own deterministic verifier. Every run exhausted its 12-hour budget. Trials are stored in each bundle's `trials/opus-5-5/`.

Reward is the maximum over every retained `submissions/<round>/report.json`, which is the verifier's own output, rather than the harness summary file. All 484 retained reports were scanned and none reached 1.0.

| Bundle | Best reward | Graded outcome | First round at best | Rounds<br/>agent / auto | Retained<br/>reports | Agent<br/>wall clock |
| --- | ---: | --- | --- | ---: | ---: | ---: |
| [`3e527b39-1359-490f-a563-828173c1df53`](3e527b39-1359-490f-a563-828173c1df53/trials/opus-5-5/) | 0.6107 | weighted score over the frozen 10,149-case manifest | `auto-47` | 15 / 47 | 62 | 12h 0m |
| [`8fc1b9be-68ab-5f53-b369-3fb4bc621933`](8fc1b9be-68ab-5f53-b369-3fb4bc621933/trials/opus-5-5/) | 0.4384 | 83 of 99 held-out always-safe checks removed, both gates 1.0 | `agent-62` | 64 / 42 | 106 | 12h 0m |
| [`ab699c94-d025-5fd3-82a7-09d56645af1b`](ab699c94-d025-5fd3-82a7-09d56645af1b/trials/opus-5-5/) | 0.2857 | 2 of 7 correction windows | `agent-3` | 22 / 47 | 69 | 12h 0m |
| [`b576fd7b-9174-5276-bd2e-a5e207030d97`](b576fd7b-9174-5276-bd2e-a5e207030d97/trials/opus-5-5/) | 0.1667 | 1 of 6 correction windows, precision and attribution 1.0 | `agent-3` | 23 / 29 | 48 | 12h 0m |
| [`d49e93a6-c4d2-5013-ab29-99fbe0cc3089`](d49e93a6-c4d2-5013-ab29-99fbe0cc3089/trials/opus-5-5/) | 0.4286 | 3 of 7 correction windows (W4, W5, W6) | `agent-56` | 56 / 143 | 199 | 12h 0m |
| **mean** | **0.3860** | **0 of 5 reached 1.0** | — | **36 / 62** | **97** | **12h 0m** |

Two figures in the harness summary files are not the headline and should not be read as one. `best_pass_rate` is not comparable across bundles: three of the five graders report `total_tests` 0 and leave it at 0.0 while scoring above zero, and on the one bundle where both are real they diverge, because removing 83 of 99 checks pays 0.4384. And on the dated-builds TypeScript bundle, `final_result.json` carries a stale `best_score` of 0.2857: that run was killed by the 12-hour wall clock and missed its own last two rounds, `agent-56` and `auto-143`, which both scored 0.428571 with `valid` true and verifier exit 0.

Each trial folder is the harness run output:

| Path | Contents |
| --- | --- |
| `final_result.json` | Agent, model, best score and round, round counts, runtime, timeout flag |
| `run_history.json` | Per-round history for the run |
| `agent_prompt.md` | Prompt the agent was given |
| `agent_output.txt` | Agent transcript (git-lfs) |
| `submissions/<round>/report.json` | The verifier's own output: score, validity, metrics, per-check details |
| `submissions/<round>/` | Also `test_output.txt`, `eval.sh`, `run_instance.log`, and `submission.tar.gz` |

## Coverage

| Keyword | Bundles |
| --- | --- |
| bounds-check-elimination | 1 |
| clean-room | 1 |
| compiler | 3 |
| dataflow-analysis | 1 |
| differential-testing | 3 |
| fuzzing | 2 |
| git | 1 |
| mir | 1 |
| optimizer | 1 |
| pytest-free | 1 |
| reimplementation | 1 |
| rust | 2 |
| rustc | 2 |
| semantics-preserving-transform | 1 |
| systems | 1 |
| systems-and-se | 1 |
| trait-solver | 1 |
| type-checker | 1 |
| type-checking | 1 |
| typescript | 2 |
| typescript-go | 1 |
| upstream-suite | 1 |
| zig | 1 |
| Keyword | Bundles |
| --- | --- |
| bounds-check-elimination | 1 |
| clean-room | 1 |
| compiler | 3 |
| dataflow-analysis | 1 |
| differential-testing | 3 |
| fuzzing | 2 |
| git | 1 |
| mir | 1 |
| optimizer | 1 |
| pytest-free | 1 |
| reimplementation | 1 |
| rust | 2 |
| rustc | 2 |
| semantics-preserving-transform | 1 |
| systems | 1 |
| systems-and-se | 1 |
| trait-solver | 1 |
| type-checker | 1 |
| type-checking | 1 |
| typescript | 2 |
| typescript-go | 1 |
| upstream-suite | 1 |
| zig | 1 |

## Dataset structure

Each bundle is one Harbor task in a directory named by its content-derived uuid5.

| Bundle | Keywords |
| --- | --- |
| [`3e527b39-1359-490f-a563-828173c1df53`](3e527b39-1359-490f-a563-828173c1df53/) | clean-room, git, pytest-free, reimplementation, systems, upstream-suite, zig |
| [`8fc1b9be-68ab-5f53-b369-3fb4bc621933`](8fc1b9be-68ab-5f53-b369-3fb4bc621933/) | bounds-check-elimination, compiler, dataflow-analysis, mir, optimizer, rust, rustc, semantics-preserving-transform, systems-and-se |
| [`ab699c94-d025-5fd3-82a7-09d56645af1b`](ab699c94-d025-5fd3-82a7-09d56645af1b/) | compiler, differential-testing, fuzzing, rust, rustc, trait-solver |
| [`b576fd7b-9174-5276-bd2e-a5e207030d97`](b576fd7b-9174-5276-bd2e-a5e207030d97/) | compiler, differential-testing, type-checking, typescript |
| [`d49e93a6-c4d2-5013-ab29-99fbe0cc3089`](d49e93a6-c4d2-5013-ab29-99fbe0cc3089/) | differential-testing, fuzzing, type-checker, typescript, typescript-go |

```
<uuid>/
├── task.toml         runner manifest, plus an [extensions.sforge] table
├── instruction.md    objective the agent reads
├── environment/      Dockerfile for the agent sandbox
├── tests/            Dockerfile and verifier, hidden from the agent
├── solution/         reference solution, with measured scores in TRUTH.md
└── trials/
    └── opus-5-5/     claude-opus-5-5 pilot run
        ├── final_result.json, run_history.json
        ├── agent_prompt.md, agent_output.txt
        └── submissions/
            └── <round>/   report.json and per-round verifier output
```

Difficulty is measured by the signed pilot in `trials/` and is never declared in a bundle, so no bundle claims a tier. Each bundle also carries an `[extensions.sforge]` table read only by the brocket harness launcher; `harbor lint` reports `unknown-config-field` for it and the task validates and runs normally.
Each bundle is one Harbor task in a directory named by its content-derived uuid5.

| Bundle | Keywords |
| --- | --- |
| [`3e527b39-1359-490f-a563-828173c1df53`](3e527b39-1359-490f-a563-828173c1df53/) | clean-room, git, pytest-free, reimplementation, systems, upstream-suite, zig |
| [`8fc1b9be-68ab-5f53-b369-3fb4bc621933`](8fc1b9be-68ab-5f53-b369-3fb4bc621933/) | bounds-check-elimination, compiler, dataflow-analysis, mir, optimizer, rust, rustc, semantics-preserving-transform, systems-and-se |
| [`ab699c94-d025-5fd3-82a7-09d56645af1b`](ab699c94-d025-5fd3-82a7-09d56645af1b/) | compiler, differential-testing, fuzzing, rust, rustc, trait-solver |
| [`b576fd7b-9174-5276-bd2e-a5e207030d97`](b576fd7b-9174-5276-bd2e-a5e207030d97/) | compiler, differential-testing, type-checking, typescript |
| [`d49e93a6-c4d2-5013-ab29-99fbe0cc3089`](d49e93a6-c4d2-5013-ab29-99fbe0cc3089/) | differential-testing, fuzzing, type-checker, typescript, typescript-go |

```
<uuid>/
├── task.toml         runner manifest, plus an [extensions.sforge] table
├── instruction.md    objective the agent reads
├── environment/      Dockerfile for the agent sandbox
├── tests/            Dockerfile and verifier, hidden from the agent
├── solution/         reference solution, with measured scores in TRUTH.md
└── trials/
    └── opus-5-5/     claude-opus-5-5 pilot run
        ├── final_result.json, run_history.json
        ├── agent_prompt.md, agent_output.txt
        └── submissions/
            └── <round>/   report.json and per-round verifier output
```

Difficulty is measured by the signed pilot in `trials/` and is never declared in a bundle, so no bundle claims a tier. Each bundle also carries an `[extensions.sforge]` table read only by the brocket harness launcher; `harbor lint` reports `unknown-config-field` for it and the task validates and runs normally.

## Reproduction

Each bundle directory is a complete Harbor task: `task.toml` is the runner manifest, `instruction.md` the objective, `environment/` the Dockerfile for the agent sandbox, `tests/` the Dockerfile and verifier, and `solution/` the reference solution with its measured scores, controls, and ground truth in `TRUTH.md`. Neither image is pulled from a registry; both are built from the bundle's own Dockerfiles, so the grader bytes reach no registry.

Point a Harbor runner at one bundle directory:

```bash
harbor run
```

For a clean preflight, `harbor lint --ignore unknown-config-field` exits 0 on these bundles. No API key is needed in either phase: grading is deterministic and calls no LLM judge, and `network_mode` is `no-network` for both the agent and the verifier. Build the arm64 images on a native arm64 builder; the measured QEMU penalty on these images is about 6.5x, which would put an emulated build of the rustc bundle outside its timeout.

## Verification and quality assurance

Every figure in this page is measured rather than asserted. Each bundle's reference solution was measured at exactly 1.0 and its null floor at exactly 0.0, and author-side control modes were run rather than assumed: `missing`, `empty`, `impossible`, `naive`, `spray`, `liar`, and `one-mechanism`. Every wrong control falls the whole way to zero, while the `one-mechanism` control lands at 1/6 and 1/7 on the two differential bundles, which is the continuous partial credit the reward claims. Each bundle declares `null_floor = 0.0` and `discrimination_weight = 0.5`, and the band between a wrong submission and an incomplete one is what that weight records.

Contamination is bounded, not eliminated. Four of the five bundles are original; the Zig port is derived from EdgeBench's public release under CC-BY-4.0 and ships git's own C source by design, so it measures porting rather than recall. Agent containers are offline, so no in-run retrieval is possible. The three differential-tester bundles grade against correction windows bracketing merged public pull requests, several with public regression tests, so catching a window demonstrates that the submitted tester discriminates; it is not evidence of independent discovery. No model memorisation test was run.
Each bundle directory is a complete Harbor task: `task.toml` is the runner manifest, `instruction.md` the objective, `environment/` the Dockerfile for the agent sandbox, `tests/` the Dockerfile and verifier, and `solution/` the reference solution with its measured scores, controls, and ground truth in `TRUTH.md`. Neither image is pulled from a registry; both are built from the bundle's own Dockerfiles, so the grader bytes reach no registry.

Point a Harbor runner at one bundle directory:

```bash
harbor run
```

For a clean preflight, `harbor lint --ignore unknown-config-field` exits 0 on these bundles. No API key is needed in either phase: grading is deterministic and calls no LLM judge, and `network_mode` is `no-network` for both the agent and the verifier. Build the arm64 images on a native arm64 builder; the measured QEMU penalty on these images is about 6.5x, which would put an emulated build of the rustc bundle outside its timeout.

## Verification and quality assurance

Every figure in this page is measured rather than asserted. Each bundle's reference solution was measured at exactly 1.0 and its null floor at exactly 0.0, and author-side control modes were run rather than assumed: `missing`, `empty`, `impossible`, `naive`, `spray`, `liar`, and `one-mechanism`. Every wrong control falls the whole way to zero, while the `one-mechanism` control lands at 1/6 and 1/7 on the two differential bundles, which is the continuous partial credit the reward claims. Each bundle declares `null_floor = 0.0` and `discrimination_weight = 0.5`, and the band between a wrong submission and an incomplete one is what that weight records.

Contamination is bounded, not eliminated. Four of the five bundles are original; the Zig port is derived from EdgeBench's public release under CC-BY-4.0 and ships git's own C source by design, so it measures porting rather than recall. Agent containers are offline, so no in-run retrieval is possible. The three differential-tester bundles grade against correction windows bracketing merged public pull requests, several with public regression tests, so catching a window demonstrates that the submitted tester discriminates; it is not evidence of independent discovery. No model memorisation test was run.

## Cite

```bibtex
@misc{brocket2026,
  title        = {brocket: adversarial terminal tasks at the edge of frontier capability},
  author       = {{Ethara.AI}},
  author       = {{Ethara.AI}},
  year         = {2026},
  howpublished = {\url{https://github.com/EtharaOrion/brocket}}
}
```



## Contact

Brocket is built by [Ethara.AI](https://github.com/Ethara-Ai). For questions about the benchmark or dataset, contact [research@ethara.ai](mailto:research@ethara.ai).

Copyright (c) 2026 Green Rider Technology LLP (Ethara AI). All rights reserved.
