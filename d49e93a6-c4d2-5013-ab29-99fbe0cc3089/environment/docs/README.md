# Checkers in this environment

| path | checker |
|---|---|
| `/opt/ts/tsc6/bin/tsc` | `typescript@6.0.3`, the last JavaScript implementation of the checker |
| `/opt/ts/dev/bin/tsc` | `typescript@7.1.0-dev.20261113.1`, a Go-native checker build |
| `/opt/ts/practice/bin/tsc` | `typescript@7.1.0-dev.20261015.1`, an older Go-native checker build |

Every toolchain is a directory under `/opt/ts/<name>/`, and `/opt/ts/<name>/bin/tsc` runs it. The
toolchains your tester is graded against follow the same layout and are not installed here.

`practice` is for checking that your tester really finds fixed bugs. Upstream fixed a few
divergences between the `practice` build and the `dev` build. A program that splits 6.0.3 from
`practice` and agrees with 6.0.3 on `dev` is exactly the kind of witness the grader credits. Your
tester is not graded against `practice`, and none of the graded bugs is present in it.

`checker-notes.md` maps the parts of the checker where a port can drift.

The fixed invocation, run in a directory that holds only `main.ts`:

    /opt/ts/<name>/bin/tsc --noEmit --strict --target es2022 --module esnext --moduleResolution bundler main.ts

No network is available. Node 22 is at `/opt/node22/bin/node` and Python 3 at `/usr/bin/python3`;
both are present in the grading environment too.
