# TRUTH

<!-- FORGE-CANARY-BEGIN -->
<!-- FORGE-CANARY-SLOT-1: 3ddccc53ce11e5863c8da9b31e5ecf88a88aa81c5837517c50653000cf9c4deb -->
<!-- FORGE-CANARY-SLOT-2: 9fd86250d3b787176068cbad3642f5444dbb5a1ae12fab88129041a8fbecc900 -->
<!-- FORGE-CANARY-SLOT-3: 0806122145c059db2a8c1cf847aed5b7954cafc1ea5184bed48b2294293eb661 -->
<!-- FORGE-CANARY-END -->

A structural conformance differential tester between TypeScript's JavaScript and native Go type checkers, with no emit.

Reference: typescript@6.0.3. Development: typescript@7.1.0-dev.20261113.1.

## Protocol

accept = status 0; reject = status 1 or 2 with a TS diagnostic; crash = other termination; timeout = 60 seconds followed by SIGKILL. Only classes are compared, not wording, ordering, positions or error-code sets. This deliberately excludes missing-diagnostic-only differences such as #4834. Both 1 and 2 are legitimate rejection exit statuses in measured native packages.

Options: `--noEmit --strict --target es2022 --module esnext --moduleResolution bundler --lib es2022 --pretty false`.

## Measured windows

| Window | Upstream fix | Mechanism | Before | After | Observed reference/native | Oracle credits | Naive inputs | Naive flips |
|---|---|---|---|---|---|---:|---:|---:|
| W1 | microsoft/typescript-go#4591 | union-matching-depth | 7.1.0-dev.20260721.1 | 7.1.0-dev.20260722.1 | accept/reject -> accept/accept | 2 | 512 | 0 |
| W2 | microsoft/typescript-go#4606 | dependent-binding-reentrance | 7.1.0-dev.20260722.1 | 7.1.0-dev.20260723.1 | accept/reject -> accept/accept | 2 | 512 | 0 |
| W3 | microsoft/typescript-go#4913 | array-linked-relation-cycle | 7.1.0-dev.20260818.1 | 7.1.0-dev.20260819.1 | accept/reject -> accept/accept | 3 | 512 | 0 |
| W4 | microsoft/TypeScript#64772 | remapped-key-constraint | 7.1.0-dev.20261013.1 | 7.1.0-dev.20261014.1 | accept/reject -> accept/accept | 2 | 512 | 0 |
| W5 | microsoft/TypeScript#64594 | reverse-mapping-accessibility | 7.1.0-dev.20261027.1 | 7.1.0-dev.20261028.1 | accept/reject -> accept/accept | 2 | 512 | 0 |
| W6 | microsoft/TypeScript#65093 | inherited-variance-layout | 7.1.0-dev.20261103.1 | 7.1.0-dev.20261104.1 | reject/accept -> reject/reject | 2 | 512 | 0 |

## Real verifier-image validation

| Submission | Reward | Gate | Caught | Precision | Attribution | Minimality | Invalid |
|---|---:|---:|---:|---:|---:|---:|---:|
| oracle | 1 | 1 | 6 | 1 | 1 | 1 | 0 |
| missing | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| empty | 0 | 1 | 0 | 1 | 0 | 0 | 0 |
| naive | 0 | 1 | 0 | 0.5267857142857142 | 0 | 0 | 0 |
| spray | 0 | 1 | 6 | 0.15769300144300144 | 0 | 1 | 0 |
| liar | 0 | 0 | 0 | 1 | 0 | 0 | 6 |

## Oracle

```json
{
  "development_splits": 0,
  "programs": 13,
  "caught_windows": 6,
  "selection": "At most three witnesses, one per family. Cyclic graphs are considered first while a full timeout margin remains. Persistent splits on the public development control are discarded; retained splits are independently repeated.",
  "evidence": "tests/controls/oracle-evidence.json and validation-matrix.json"
}
```

## Harbor packaging checks

```json
{
  "oracle": {
    "oracle__adhoc": {
      "n_trials": 1,
      "n_errors": 0,
      "metrics": [
        {
          "attribution": 1,
          "caught": 6,
          "credited": 6,
          "graded": 6,
          "invalid": 0,
          "minimality": 1,
          "precision": 1,
          "recall": 1,
          "reward": 1,
          "validity_gate": 1,
          "witnesses_read": 15
        }
      ],
      "pass_at_k": {},
      "reward_stats": {
        "reward": {
          "1": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "validity_gate": {
          "1": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "recall": {
          "1": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "precision": {
          "1": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "attribution": {
          "1": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "minimality": {
          "1": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "caught": {
          "6": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "graded": {
          "6": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "invalid": {
          "0": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "credited": {
          "6": [
            "harbor-bundle__8TqUrFD"
          ]
        },
        "witnesses_read": {
          "15": [
            "harbor-bundle__8TqUrFD"
          ]
        }
      },
      "exception_stats": {}
    }
  },
  "nop": {
    "nop__adhoc": {
      "n_trials": 1,
      "n_errors": 0,
      "metrics": [
        {
          "attribution": 0,
          "caught": 0,
          "credited": 0,
          "graded": 6,
          "invalid": 0,
          "minimality": 0,
          "precision": 0,
          "recall": 0,
          "reward": 0,
          "validity_gate": 0,
          "witnesses_read": 0
        }
      ],
      "pass_at_k": {},
      "reward_stats": {
        "reward": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "validity_gate": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "recall": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "precision": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "attribution": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "minimality": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "caught": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "graded": {
          "6": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "invalid": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "credited": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        },
        "witnesses_read": {
          "0": [
            "harbor-bundle__gUFVapG"
          ]
        }
      },
      "exception_stats": {}
    }
  },
  "oracle_errors": 0,
  "nop_errors": 0,
  "cache_override": {
    "change": "Only optional compiler-cache ARG default changed for local Harbor builds; immutable final image base, compiler files, instructions, grader, tests and oracle unchanged.",
    "cache": "checker-author-cache:907e"
  }
}
```

## Qualification

```json
{
  "budget_seconds": 300,
  "workers": 1,
  "seed": 500,
  "inputs_per_window": [
    512,
    512,
    512,
    512,
    512,
    512
  ],
  "scope": "Independent productions for generic interfaces, inheritance, function members, unions, intersections, mapped remapping, keyof intersection constraints, indexed access, Readonly/Required, private/protected classes, destructuring, discriminated unions, overload/assertion declarations, optional recursive arrays, and generic calls. No graph dependency model or deliberate pairing of the mapped key domain with its indexed access.",
  "superseded": "v1 concatenated independent constructs into mostly rejected programs. v2 samples standalone productions to avoid rejection masking. Both are retained as measured evidence; qualification uses only v2.",
  "excluded_by_naive": []
}
```

## Byte cap

```json
{
  "cap_bytes": 3200,
  "max_credited_source_bytes": 2592,
  "rationale": "The largest credited family is a pair of at least 34 array-linked interfaces. 3200 bytes admits the measured finite ring schemas without rewarding large test dumps; all other families are substantially smaller."
}
```

## Intentional background differences

```json
{
  "options_note": "No deprecated options or floating target/module/lib defaults. stableTypeOrdering is intentionally NOT set: it changes the fixed reference's inherited-variance result. Persistent intentional stable-ordering differences are excluded by L5 instead.",
  "release_notes": "https://www.typescriptlang.org/docs/handbook/release-notes/typescript-6-0.html#the---stabletypeordering-flag",
  "reference_last_six": "6.0.3",
  "persistent_issue": "microsoft/typescript-go#4817",
  "persistent_flips": 0,
  "measured_windows": [
    {
      "id": "W1",
      "pre": "7.1.0-dev.20260721.1",
      "post": "7.1.0-dev.20260722.1",
      "mechanism": "union-matching-depth",
      "fix": "microsoft/typescript-go#4591",
      "commit": "90b40e8b21ff73bdaabdda4ec154adbb1e8e0ae5",
      "note": "Match unions in nesting-depth order; excludes the independent CFA fix in this nightly by structural family.",
      "before": [
        "accept",
        "reject"
      ],
      "after": [
        "accept",
        "reject"
      ],
      "credited": false
    },
    {
      "id": "W2",
      "pre": "7.1.0-dev.20260722.1",
      "post": "7.1.0-dev.20260723.1",
      "mechanism": "dependent-binding-reentrance",
      "fix": "microsoft/typescript-go#4606",
      "commit": "36d9c9b1296de748f7cf5d7ca648918097cc5167",
      "note": "Preserve dependent destructuring narrowing through re-entrant overloaded assertion checking.",
      "before": [
        "accept",
        "reject"
      ],
      "after": [
        "accept",
        "reject"
      ],
      "credited": false
    },
    {
      "id": "W3",
      "pre": "7.1.0-dev.20260818.1",
      "post": "7.1.0-dev.20260819.1",
      "mechanism": "array-linked-relation-cycle",
      "fix": "microsoft/typescript-go#4913",
      "commit": "12548e2a13b61004a2464686df7cbfe88640bbf9",
      "note": "Remove spurious depth overflow on finite cyclic array-linked interfaces.",
      "before": [
        "accept",
        "reject"
      ],
      "after": [
        "accept",
        "reject"
      ],
      "credited": false
    },
    {
      "id": "W4",
      "pre": "7.1.0-dev.20261013.1",
      "post": "7.1.0-dev.20261014.1",
      "mechanism": "remapped-key-constraint",
      "fix": "microsoft/TypeScript#64772",
      "commit": "a0a0ff55cab4a1f81b7123ab219c97a2f1ed703d",
      "note": "Restore keyof simplification for mapped name types.",
      "before": [
        "accept",
        "reject"
      ],
      "after": [
        "accept",
        "reject"
      ],
      "credited": false
    },
    {
      "id": "W5",
      "pre": "7.1.0-dev.20261027.1",
      "post": "7.1.0-dev.20261028.1",
      "mechanism": "reverse-mapping-accessibility",
      "fix": "microsoft/TypeScript#64594",
      "commit": "b6a965883b8e357d89b4574c134b4f971bb70253",
      "note": "Exclude non-public keys from reverse mapping.",
      "before": [
        "accept",
        "reject"
      ],
      "after": [
        "accept",
        "reject"
      ],
      "credited": false
    },
    {
      "id": "W6",
      "pre": "7.1.0-dev.20261103.1",
      "post": "7.1.0-dev.20261104.1",
      "mechanism": "inherited-variance-layout",
      "fix": "microsoft/TypeScript#65093",
      "commit": "f0accfdfe02cb199b0f6c8ccab68e3419f33862a",
      "note": "Restore inherited member ordering through empty subinterfaces.",
      "before": [
        "accept",
        "reject"
      ],
      "after": [
        "accept",
        "reject"
      ],
      "credited": false
    }
  ]
}
```

## Measured reserves and exclusions

```json
[
  {
    "ids": [
      "4768"
    ],
    "reason": "TS repro rejects on both implementations; upstream confirms the JS variant is intentional semantic alignment."
  },
  {
    "ids": [
      "4817",
      "4827",
      "4862"
    ],
    "reason": "Documented stable type ordering; 4817 and 4827 measured with and without stableTypeOrdering; persistent through development. 4862 dependency-based report was not installed or measured."
  },
  {
    "ids": [
      "65011"
    ],
    "reason": "Reduced TS case still rejects in development; closed as duplicate, not proof of a merged fix."
  },
  {
    "ids": [
      "65090",
      "65048"
    ],
    "reason": "Reference and early native both reject with 2339/2373; development accepts, so native correction does not come into agreement with fixed reference."
  },
  {
    "ids": [
      "65174"
    ],
    "reason": "Measured persistent import-assertion difference; upstream documents removal. 65142 is also documented intentional expando behavior, not measured."
  },
  {
    "ids": [
      "4735",
      "4655",
      "4599",
      "4603",
      "64165"
    ],
    "reason": "JS 6.0.3 also crashes on each measured reduced shape. Correcting native makes it disagree with the frozen reference, not a graded agreement flip."
  },
  {
    "ids": [
      "4586",
      "4442",
      "64530"
    ],
    "reason": "Reference retains the old error while corrected native accepts. 64530 pre native crashes on measured shape. Not agreement flips."
  },
  {
    "ids": [
      "4691"
    ],
    "reason": "Measured positive flip shares W1's adjacent builds; reserved instead of adding an indistinguishable second binary window."
  },
  {
    "ids": [
      "4820",
      "64280"
    ],
    "reason": "Reduced samples showed no outcome-class change."
  },
  {
    "ids": [
      "4834"
    ],
    "reason": "Only diagnostic code set changes; deliberately ignored by the chosen outcome classes."
  },
  {
    "ids": [
      "65450"
    ],
    "reason": "Positive measured flip Nov12->Nov13. Latest post equals the only current development build; excluded to keep graded builds out of the agent image."
  },
  {
    "ids": [
      "65389",
      "4819",
      "64955"
    ],
    "reason": "Reviewed upstream reports, not measured: first is multi-file; 4819 requires external three.js types; 64955 closed by-design and JS itself overflows, not a valid fixed-reference agreement window."
  }
]
```

## Limits

- No external frontier-agent pilot or signed attestation; cap HOLD:PILOT_REQUIRED (attestation-unavailable).
- Version independence is an explicit rule plus literal scanning, not a proof against arbitrary obfuscation.
- Native packages contain multiple upstream changes between daily builds. npm adjacency and direct witness flips are measured; no claim that an entire nightly contains only one commit. Each chosen structural witness is attributed to its documented upstream correction.
- Local LSP was unavailable (typescript-language-server not installed); strict native TypeScript compiler checking was run on EC2 instead.
- No timing-only performance improvement is graded. A real 60-second classifier fixture tests timeout handling; none of the six graded witnesses requires a timeout.

## EC2 commands

```sh
ssh brocket
docker run --cpus 2 --memory 6g --network none -v "$HOME/smoldata-authoring/tsc-checker-differential:/work" node:26.13.0-bookworm-slim node /work/prep.mts
nice -n 10 docker build -f "$HOME/smoldata-authoring/tsc-checker-differential/Cache.Dockerfile" -t checker-author-cache:907e "$HOME/smoldata-authoring/tsc-checker-differential/compilers"
nice -n 10 docker build --build-arg COMPILER_CACHE_IMAGE=checker-author-cache:907e -t checker-work:907e "$HOME/smoldata-authoring/tsc-checker-differential/bundle/environment"
nice -n 10 docker build --build-arg COMPILER_CACHE_IMAGE=checker-author-cache:907e -t checker-judge:907e "$HOME/smoldata-authoring/tsc-checker-differential/bundle/tests"
nice -n 10 docker run --cpus 2 --memory 6g --network none -v "$HOME/smoldata-authoring/tsc-checker-differential/bundle/solution:/root/oracle:ro" -v "$HOME/smoldata-authoring/tsc-checker-differential/bundle/tests/controls:/evidence" checker-judge:907e node /tests/controls/matrix.mts
docker run --cpus 2 --memory 6g --network none -e COMPILER_ROOT=/work/compilers -v "$HOME/smoldata-authoring/tsc-checker-differential:/work" node:26.13.0-bookworm-slim node /work/bundle/tests/controls/gate.mts --out /work/bundle/tests/controls/gate-evidence-v2.json
docker run --cpus 2 --memory 6g --network none -e COMPILER_ROOT=/work/compilers -v "$HOME/smoldata-authoring/tsc-checker-differential:/work" node:26.13.0-bookworm-slim node /work/bundle/tests/controls/oracle_check.mts --out /work/bundle/tests/controls/oracle-evidence.json
harbor run -p "$HOME/smoldata-authoring/tsc-checker-differential/harbor-bundle" -a oracle -n 1 --override-cpus 2 --override-memory-mb 6144 --jobs-dir "$HOME/smoldata-authoring/tsc-checker-differential/harbor-jobs" --job-name checker-oracle --no-delete
harbor run -p "$HOME/smoldata-authoring/tsc-checker-differential/harbor-bundle" -a nop -n 1 --override-cpus 2 --override-memory-mb 6144 --jobs-dir "$HOME/smoldata-authoring/tsc-checker-differential/harbor-jobs" --job-name checker-nop --no-delete
```
