# Type checking background

TypeScript is structurally typed. Assignability relates source and target members,
not just declaration names. Generic inference combines information from function
arguments and contextual types; annotations, constraints, unions, intersections,
conditional types, mapped keys, and callable members can all affect that information.

Control-flow analysis narrows types at use sites. A union discriminant can carry
information about another property, including after a const destructuring binding.
Function overload resolution and assertion signatures can themselves require type
information and interact with that analysis.

`--noEmit` performs syntactic and semantic checking without writing JavaScript or
declaration files. `--strict` makes the comparison independent of the installed
compiler's default strictness. Explicit target, module, module resolution, and lib
settings avoid configuration drift. Run each candidate in an empty scratch directory
with only its single source file and no tsconfig or package dependencies.

The shipped checker packages include standard library declarations; these are not
external dependencies of a witness. Do not compare diagnostic prose, positions, or
ordering: they are not stable between implementations.

This neutral background note is authored for this benchmark. LICENSE contains the
Apache-2.0 terms shipped with the TypeScript compiler and its standard declarations.
