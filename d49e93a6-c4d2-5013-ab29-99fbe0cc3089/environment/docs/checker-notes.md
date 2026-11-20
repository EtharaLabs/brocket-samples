# Where a port of the TypeScript checker can drift

The Go checker is a line-by-line port of the JavaScript one. The two run the same algorithms, so
they agree on ordinary code. They drift where the original relies on something a port has to
rebuild by hand: JavaScript's own number and string semantics, the exact order in which lazy work
happens, identity and caching of types, and small conditions inside large functions that are easy
to transcribe slightly wrong. These notes map the checker's subsystems. They describe how the
original behaves, not where any particular build goes wrong.

## Scanner and parser

- Contextual keywords such as `type`, `of`, `async`, `await`, `declare`, `abstract`, `accessor`,
  `satisfies` and `out` are identifiers in most positions. The parser decides by lookahead, and
  some decisions depend on whether a line terminator follows the word.
- Automatic semicolon insertion, escaped keywords (`\u0069f`), numeric separators, and the
  regular-expression grammar (named groups, flags, Unicode sets) are all scanner-level rules.
- Many errors that look syntactic are reported later by the checker's grammar pass, so a program
  can parse identically in both and still be judged differently.

## Binder and declaration merging

- Declarations with one name merge by symbol flags: interface with interface, namespace with
  namespace, class with interface, function with namespace, enum with enum.
- Which pairs are legal, and which produce a duplicate-identifier error, is decided from those
  flags. Members merge too: properties, methods, index signatures, get and set accessors.
- Expando assignments (`f.x = 1` after `function f`) add members after declaration.

## Constant evaluation

- Enum members and constant expressions are folded with JavaScript arithmetic: `NaN`, `Infinity`,
  `-0`, integer overflow, string concatenation, and number-to-string conversion. A port must
  reproduce each of these exactly.

## Control-flow analysis

- Narrowing walks flow nodes backwards from a reference. A reference is an identifier, `this`, a
  property access, or an element access with a literal or constant key, and two references match
  only under precise rules.
- Narrowing comes from `typeof`, `instanceof`, `in`, equality, truthiness, discriminant
  properties, type predicates and assertion functions.
- Loops need a fixpoint. A variable whose type depends on itself through a loop is circular, and
  the original reports implicit `any` for it only in specific circumstances.

## Iteration and error recovery

- `for-of`, spread and destructuring compute iteration types for arrays, strings, iterables and
  unions of these. When part of a type is not iterable, the checker reports it and then continues
  with some recovery type.

## Inference

- Type arguments are inferred from candidates collected with priorities. `never`, `any`,
  `unknown`, literal types and `const` type parameters each have special handling as sources and
  targets.
- Inference into union and intersection targets matches constituents first and infers from the
  rest. Defaults, constraints and contextual return types all take part in the outcome.

## Type relations

- Assignability, subtyping, comparability and identity are separate relations sharing one engine.
- Recursive types are compared with identity-based cycle detection and depth limits. TS2589
  ("excessively deep") appears when those limits are hit.
- Results are cached, and the cache key decides when two types count as the same.

## Mapped, indexed-access and conditional types

- Mapped types may be homomorphic, may carry `as` clauses that rename or filter keys, and keep
  modifiers.
- `keyof` of a mapped type and indexed access into a generic type are simplified only in
  particular shapes. Otherwise they stay deferred.
- Conditional types distribute over unions, `infer` introduces type variables, and template
  literal types and intrinsic string mappings (`Uppercase` and the rest) follow JavaScript's
  string functions.

## Classes and members

- The checker validates modifier order and combinations, abstract members, accessors and their
  pairing, parameter properties, decorators, `this` types, and inherited members resolved through
  the base types.
- The Go checker resolves members lazily. Anything that depends on the order of resolution
  (circularity detection, `this`-typed members inherited from an intersection) has to give the
  same answer whatever order the work happens in.

## Practical notes

- One divergence often shows up across many programs. Shrink each one to the smallest program
  that still splits the two checkers, and name it after the behaviour it exercises.
- Some divergences are permanent: they are present on every Go build, including the newest. A
  divergence that is still present on `/opt/ts/dev` is one of those.
