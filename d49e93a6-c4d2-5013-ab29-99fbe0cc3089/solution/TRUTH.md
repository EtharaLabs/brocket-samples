# TRUTH

The task is a differential tester between the TypeScript 6 JavaScript checker and the Go-native TypeScript 7 checker. The baseline checker is `typescript@6.0.3` and every
graded checker is a dated Go-native build. Each program is the single file `main.ts`, checked
with `tsc --noEmit --strict --target es2022 --module esnext --moduleResolution bundler main.ts`. The flag set is fixed, so the deliberate 6 to 7 option and default changes never enter a comparison. Builds up to 7.0.0-dev.20260707.2 come from @typescript/native-preview and later ones from typescript@7.1.0-dev, because microsoft/typescript-go was archived on 2026-08-20 and the Go checker continued in microsoft/TypeScript.

## What counts as a disagreement

The outcome classes are accept, reject, crash, hang. accept is exit 0; reject is a non-zero exit with at least one error TS diagnostic and no crash marker; crash is a Go panic or fatal error, a Node uncaught throw or stack trace, or a non-zero exit with no diagnostic; hang is the 60 s wall limit. A diagnostic difference inside one class is not a disagreement.

## The graded set

7 fixes, 7 distinct mechanisms.

| window | fix | mechanism | pre-fix | post-fix | 6.0.3 / pre / post | reference family | shown on pre |
| --- | --- | --- | --- | --- | --- | --- | --- |
| W1 | microsoft/typescript-go#3496 | error propagation through non-iterable unions in for-of | `@typescript/native-preview@7.0.0-dev.20260423.1` | `@typescript/native-preview@7.0.0-dev.20260424.1` | accept / reject TS2339 / accept | for-of over a union with a non-iterable member | 8 |
| W2 | microsoft/typescript-go#3672 | accessor and property duplicate-declaration check across merged interfaces | `@typescript/native-preview@7.0.0-dev.20260430.1` | `@typescript/native-preview@7.0.0-dev.20260501.1` | accept / reject TS2300 / accept | accessor and property merged across interface declarations | 7 |
| W3 | microsoft/typescript-go#3695 | inference from never into union targets | `@typescript/native-preview@7.0.0-dev.20260505.1` | `@typescript/native-preview@7.0.0-dev.20260506.1` | accept / reject TS2322 / accept | inference from never into a union target | 6 |
| W4 | microsoft/typescript-go#3869 | using followed by a line terminator parsed as a declaration | `@typescript/native-preview@7.0.0-dev.20260515.1` | `@typescript/native-preview@7.0.0-dev.20260516.1` | accept / reject TS1155 / accept | using as an identifier before a line terminator | 5 |
| W5 | microsoft/typescript-go#3932 | NaN-valued enum members receiving distinct literal types | `@typescript/native-preview@7.0.0-dev.20260518.1` | `@typescript/native-preview@7.0.0-dev.20260519.1` | accept / reject TS2322 / accept | enum members with NaN values | 4 |
| W6 | microsoft/typescript-go#4691 | over-eager constructor-reference matching in control-flow narrowing | `typescript@7.1.0-dev.20260721.1` | `typescript@7.1.0-dev.20260722.1` | accept / reject TS7022 / accept | narrowing through element access in a loop body | 3 |
| W7 | microsoft/TypeScript#64772 | keyof simplification for generic mapped types with as clauses | `typescript@7.1.0-dev.20261013.1` | `typescript@7.1.0-dev.20261014.1` | accept / reject TS2536 / accept | keyof of a generic mapped type with a filtering as clause | 2 |

Each window is the pair of consecutive published builds that brackets its merge, so a fix
landing in another span cannot be credited by the same witness.

## The reference tester

It walks 10 structural families of 15 programs in about
12 seconds per toolchain. On `typescript@7.1.0-dev.20261113.1`, which carries every graded fix,
it reports 1 witness: the renaming-as-clause keyof program, a background divergence that persists on every Go build measured.
It catches 7 of 7 graded windows. Every witness it reports is one it observed itself, and the grader recompiles each under 6.0.3, pre and post before crediting it; the oracle scores reward 1.0 and an empty submission 0.0 under tests/test.sh.

## The naive baseline

The baseline samples from a grammar covering 15 construct families
(object and union type aliases, arrays, interfaces with properties, methods and accessors, repeated interface names, enums with NaN and Infinity initialisers, declared bindings, for-of loops, ts-ignore comments, generic functions with const and defaulted type parameters, conditional types, mapped types with as clauses, keyof, using as identifier and declaration, classes with constructor checks, element access in narrowing conditions), with no model of a checker port: each construct is sampled independently and never composed on purpose into the shape a port gets wrong.
It is given 300 seconds per window on 8 workers at seed 500.

On the graded set it reached nothing:

| window | programs tried | splits sampled | flips |
| --- | --- | --- | --- |
| W1 | 481 | 0 | 0 |
| W2 | 535 | 0 | 0 |
| W3 | 427 | 0 | 0 |
| W4 | 494 | 0 | 0 |
| W5 | 474 | 0 | 0 |
| W6 | 511 | 0 | 0 |
| W7 | 505 | 0 | 0 |

## Limits of this record

A keyof over a generic mapped type with a renaming as clause is rejected by 6.0.3 (TS2322) and accepted by every Go build measured through the development build. It splits every window's pre and post build alike, so it is background: never credited, never penalised, and it competes for the witness allowance.

About fifteen further upstream fixes were measured and left out, mostly because typescript@6.0.3 shares the bug (typescript-go#4586, #4735, #4655, #4603, #4599, #4442, #3288, #3503), because the fix adds a check 6.0.3 lacks (#4881, #4676, TypeScript#64885), or because no single-file class change was observable (#3426, TypeScript#65080). With no reserve, the graded set is exactly the seven windows above. The naive baseline split nothing in 3427 programs, so the gate shows that blind generation reaches no window; it does not by itself measure how hard a deliberate search is.
