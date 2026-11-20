"""Grade one submission against the frozen case manifest and write the Harbor reward.

Fails closed. A missing or unreadable manifest, a submission that does not rebuild, or a
red-line violation produces reward 0.0 rather than an absent or partial score, and the
denominator is always the frozen manifest so an aborted script cannot shrink it.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.dont_write_bytecode = True

import suite  # noqa: E402


def load_manifest(path: Path) -> tuple[suite.GradedCase, ...]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schema") != suite.SCHEMA:
        raise SystemExit(f"manifest schema is not {suite.SCHEMA}: {document.get('schema')!r}")
    return tuple(
        suite.GradedCase(
            script=row["script"],
            number=int(row["number"]),
            title=row.get("title", ""),
            drift=bool(row["drift"]),
            composition=bool(row["composition"]),
        )
        for row in document["cases"]
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--candidate-bin", required=True, type=Path, help="dir holding the built git")
    parser.add_argument("--source", required=True, type=Path, help="the pinned git source tree")
    parser.add_argument("--reward", required=True, type=Path)
    parser.add_argument("--per-family", type=Path)
    parser.add_argument("--script-timeout", type=int, default=900)
    parser.add_argument("--zero", action="store_true", help="record reward 0.0 without running")
    args = parser.parse_args(argv)

    cases = load_manifest(args.manifest)
    if args.zero:
        empty = suite.score(cases, {})
        suite.write_reward(args.reward, empty)
        if args.per_family is not None:
            args.per_family.write_text(json.dumps(empty.per_family, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(empty.reward_document(), sort_keys=True))
        return 0

    environment = {
        "PATH": "/usr/bin:/bin",
        "HOME": os.environ.get("HOME", "/tmp"),
        "TZ": "UTC",
        "LC_ALL": "C",
        "LANG": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    runs: dict[str, suite.ScriptRun] = {}
    for script in sorted({case.script for case in cases}):
        runs[script] = suite.run_script(
            script,
            args.candidate_bin,
            args.source,
            timeout=args.script_timeout,
            env=environment,
        )

    result = suite.score(cases, runs)
    suite.write_reward(args.reward, result)
    if args.per_family is not None:
        args.per_family.write_text(json.dumps(result.per_family, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result.reward_document(), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
