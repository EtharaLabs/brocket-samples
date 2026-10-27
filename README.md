<p align="center"><img src="images/hero.svg" alt="brocket" width="720"></p>

# brocket: samples

<p align="center"><b>The samples lane: 3 of 30 Harbor task bundles.</b></p>

<p align="center"><a href="#summary"><img src="https://img.shields.io/badge/bundles-3_of_30-845EF7" alt="bundles: 3 of 30"></a> <a href="#evidence-status"><img src="https://img.shields.io/badge/sealed-0-845EF7" alt="sealed: 0"></a> <a href="#difficulty-tiers"><img src="https://img.shields.io/badge/difficulty-measured-845EF7" alt="difficulty: measured"></a></p>

<p align="center"><sub><a href="#abstract">Abstract</a> | <a href="#summary">Summary</a> | <a href="#difficulty-tiers">Difficulty tiers</a> | <a href="#evidence-status">Evidence status</a> | <a href="#coverage">Coverage</a> | <a href="#dataset-structure">Dataset structure</a> | <a href="#verification-and-quality-assurance">Verification and quality assurance</a> | <a href="#reproduction">Reproduction</a> | <a href="#cite">Cite</a> | <a href="#license">License</a> | <a href="#contact">Contact</a></sub></p>

## Abstract

The curated lane of this corpus: at most 30 Harbor task bundles, every anchor seated first and every other bundle in seal order. Bundles past that ceiling live in `delivery/`.

Each bundle is one Harbor task in a directory named by its content-derived uuid5, so the name doubles as an integrity check. This page is rendered from the resident bundles on every reconcile; a value a bundle does not carry reads `absent`, and the page never fills one in.

## Summary

| Property | Value |
| --- | --- |
| Bundles | 3 of 30 |
| Sealed | 0 of 3 |
| Registrations | unregistered (3) |
| Audit verdicts | none (3) |
| Harbor schema | 1.4 (3) |

## Difficulty tiers

Difficulty is measured by the signed pilot alone and never declared in a bundle, so this page states no tier a bundle claims.

## Evidence status

The verdict is the audit outcome recorded at the sealed digest, and `none` means no verdict has landed for that digest yet. Only an authoring run removes a bundle from this lane, so removal waits for the next one.

| uuid | Verdict | Sealed digest | Stream |
| --- | --- | --- | --- |
| 62b54382-a910-5b29-ad0e-1efa993cc615 | none | absent | none |
| f5e2f024-213f-58cf-aa21-594a53624a8b | none | absent | none |
| f6424bd2-3d99-5647-9f59-6323ace5d907 | none | absent | none |

## Coverage

| Keyword | Bundles |
| --- | --- |
| arm64-native | 1 |
| bounded-continuous | 1 |
| combinatorial-optimization | 1 |
| edgebench | 1 |
| ffmpeg-swscale | 1 |
| image-scaling | 1 |
| libpcap-1.10.6 | 1 |
| mephisto | 1 |
| optimization | 1 |
| packet-filter-compiler-codegen | 1 |
| pixel-format-conversion | 1 |
| reimplementation-fidelity | 1 |
| rust | 1 |
| simd | 1 |
| systems-and-se | 1 |
| systems-software-engineering | 1 |

## Dataset structure

| Bundle | Task | Keywords | Registration | Sealed at | Tier |
| --- | --- | --- | --- | --- | --- |
| [`62b54382-a910-5b29-ad0e-1efa993cc615`](62b54382-a910-5b29-ad0e-1efa993cc615/) | `edgebench/libpcap_bpf_codegen_fidelity` | bounded-continuous, libpcap-1.10.6, optimization, packet-filter-compiler-codegen, reimplementation-fidelity, systems-and-se | unregistered | unsealed | - |
| [`f5e2f024-213f-58cf-aa21-594a53624a8b`](f5e2f024-213f-58cf-aa21-594a53624a8b/) | `edgebench/p6zeta_zero_one_ip_solver_from_scratch` | combinatorial-optimization, edgebench, mephisto | unregistered | unsealed | - |
| [`f6424bd2-3d99-5647-9f59-6323ace5d907`](f6424bd2-3d99-5647-9f59-6323ace5d907/) | `edgebench/ffmpeg_swscale_reimplementation` | arm64-native, ffmpeg-swscale, image-scaling, pixel-format-conversion, rust, simd, systems-software-engineering | unregistered | unsealed | - |

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#131a33","primaryTextColor":"#e8ecff","primaryBorderColor":"#845EF7","lineColor":"#22d3ee","fontFamily":"monospace"}}}%%
flowchart LR
    bundle["&lt;uuid&gt;/"]
    bundle --> n0["task.toml<br/>runner manifest"]
    bundle --> n1["instruction.md<br/>objective the agent reads"]
    bundle --> n2["environment/<br/>agent sandbox image"]
    bundle --> n3["tests/<br/>verifier, hidden from the agent"]
    bundle --> n4["solution/<br/>private oracle"]
    bundle --> n5["README.md"]
    bundle --> n6["inspect.html"]
    bundle --> n7["inspector.html"]
    bundle --> n8["plots/"]
    bundle --> n9["trajectories/"]
    bundle --> n10["trajectory/"]
```

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#131a33","primaryTextColor":"#e8ecff","primaryBorderColor":"#845EF7","lineColor":"#22d3ee","fontFamily":"monospace"}}}%%
flowchart LR
    staging["staging/"]
    staging --> samples["samples/<br/>3 of 30"]
    samples --> delivery["delivery/<br/>0 of 10000"]
    delivery --> stock["stock/<br/>0 of 10000"]
```

## Verification and quality assurance

Each bundle's signed provenance carrier holds its screening roots, screening instant, and absolute expiry. Placement moves that carrier into the private derivation set, which this page never reads, so reconcile lists no root it cannot verify here.

## Reproduction

Each bundle directory is a complete Harbor task: `task.toml` is the runner manifest, `instruction.md` the objective, `environment/` the sandbox image, and `tests/` the verifier. Point a Harbor runner at one bundle directory to reproduce it; `solution/` stays private.

## Cite

```bibtex
@misc{brocket2026,
  title        = {brocket: adversarial terminal tasks at the edge of frontier capability},
  author       = {Ethara AI},
  year         = {2026},
  howpublished = {\url{https://github.com/EtharaOrion/brocket}}
}
```

The reference frontier this project is built against is cited separately.

```bibtex
@misc{edgebench2026,
  title         = {EdgeBench: Unveiling Scaling Laws of Learning from Real-World Tasks},
  year          = {2026},
  eprint        = {2607.05155},
  archivePrefix = {arXiv},
  primaryClass  = {cs.CL}
}
```

## License

The repository is licensed under the terms in [LICENSE](LICENSE). The twelve touchstones in [touchstones/](touchstones/) are EdgeBench public task definitions, redistributed under the CC-BY-4.0 license of the EdgeBench dataset, and the vendored [harness/](harness/) extension carries the Apache-2.0 license of its upstream.

## Contact

[Ethara AI on GitHub](https://github.com/Ethara-Ai), [SECURITY.md](SECURITY.md) for a private report, and [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution route.

---

## Copyright

Copyright (c) 2026 Green Rider Technology LLP (Ethara AI). All rights reserved.
