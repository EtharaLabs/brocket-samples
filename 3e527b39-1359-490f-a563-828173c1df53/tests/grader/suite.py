"""Grade a candidate git against git's own test suite, and freeze the graded case set.

The suite is run through the `GIT_TEST_INSTALLED` path `t/README` documents, so the binary
under test is never built from the reference source. Three reference runs select the graded
cases before any rollout: the cases real git passes (R), the cases a no-op stub still passes
(N, which exercise the suite's own helpers rather than the candidate), and the cases the frozen
oracle passes (O). The graded set is ``O & R - N``, so the oracle scores exactly 1.0 and a case
no candidate could distinguish is excluded.

Two mechanical labels weight each case. A drift case sits in a script git changed between two
tags, read from git's own history. A composition case exercises several subcommands in one test
body, which is the behavior an implementation of isolated per-command handlers fails.

A case is identified by its script and its TAP number rather than its name, because a title may
interpolate shell variables and so differs between the static script and the emitted TAP line.
Skipped tests still emit a numbered line, so numbering is stable inside one frozen tag.
"""

from __future__ import annotations

import json
import re
import subprocess
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

SCHEMA = "brocket.suite-manifest/v1"

# Holistic reward: the share of a script's graded cases a candidate must pass for that script
# to count at all. A command that works in the common case but breaks on its flags, error paths
# or output format is not a working command, so a script earns its weight only when every graded
# case of every script by construction.
SCRIPT_COMPLETENESS = 1.00
DRIFT_FACTOR = 4
COMPOSITION_FACTOR = 2
COMPOSITION_MIN_DISTINCT = 3

_TAP_CASE = re.compile(r"^(?P<not>not )?ok(?: (?P<number>\d+))?(?: - )?(?P<name>.*)$")
_BAIL = re.compile(r"^Bail out!")
_PLAN = re.compile(r"^1\.\.(?P<count>\d+)\s*$")
_TEST_OPEN = re.compile(
    r"^test_expect_(?P<kind>success|failure)\s+(?P<rest>.*?)\s*(?P<quote>'|\")\s*$"
)
_TITLE = re.compile(r"""^(?:(?P<prereq>[A-Z0-9_,!]+)\s+)?(?P<title>'[^']*'|"[^"]*"|\S+)\s*$""")
# A global option that takes a separate value, so the subcommand sits one token further on.
_VALUED_GLOBAL = frozenset({"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"})


@dataclass(frozen=True, slots=True)
class TapCase:
    """One emitted TAP assertion."""

    number: int
    name: str
    ok: bool
    skipped: bool


@dataclass(frozen=True, slots=True)
class ScriptRun:
    """What one test script reported for one binary."""

    script: str
    cases: tuple[TapCase, ...]
    bailed: bool
    plan: int | None
    exit_code: int
    timed_out: bool = False

    @property
    def usable(self) -> bool:
        """Whether the run reported a complete, non-aborted plan."""
        return not self.bailed and not self.timed_out and self.plan == len(self.cases)

    def passed_numbers(self) -> frozenset[int]:
        """The numbers this run passed; an aborted run passes nothing."""
        if self.bailed or self.timed_out:
            return frozenset()
        return frozenset(case.number for case in self.cases if case.ok and not case.skipped)


@dataclass(frozen=True, slots=True)
class TestBlock:
    """One static ``test_expect_success`` or ``test_expect_failure`` block of a script."""

    ordinal: int
    kind: str
    title: str
    body: str


@dataclass(frozen=True, slots=True)
class GradedCase:
    """One case of the frozen manifest."""

    script: str
    number: int
    title: str
    drift: bool
    composition: bool

    @property
    def weight(self) -> int:
        return (DRIFT_FACTOR if self.drift else 1) * (COMPOSITION_FACTOR if self.composition else 1)

    def document(self) -> dict[str, object]:
        return {
            "script": self.script,
            "number": self.number,
            "title": self.title,
            "drift": self.drift,
            "composition": self.composition,
            "weight": self.weight,
        }


def parse_tap(text: str) -> tuple[tuple[TapCase, ...], bool, int | None]:
    """The cases, whether the script bailed, and its declared plan."""
    cases: list[TapCase] = []
    bailed = False
    plan: int | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if _BAIL.match(line):
            bailed = True
            continue
        if (planned := _PLAN.match(line)) is not None:
            plan = int(planned["count"])
            continue
        match = _TAP_CASE.match(line)
        if match is None or match["number"] is None:
            continue
        name = match["name"].strip()
        cases.append(
            TapCase(
                number=int(match["number"]),
                name=re.sub(r"\s*#\s*(skip|TODO).*$", "", name, flags=re.IGNORECASE).strip(),
                ok=match["not"] is None,
                skipped=re.search(r"#\s*skip", name, re.IGNORECASE) is not None,
            )
        )
    return tuple(cases), bailed, plan


def parse_test_blocks(script_text: str) -> tuple[TestBlock, ...]:
    """Every test block of a script, in declaration order, which is TAP order.

    Only the one-line-open form git's suite uses is recognized: the invocation ends with the
    opening quote of the body, and the body closes on a line holding that quote alone.
    """
    blocks: list[TestBlock] = []
    lines = script_text.splitlines()
    index = 0
    ordinal = 0
    while index < len(lines):
        opened = _TEST_OPEN.match(lines[index])
        if opened is None:
            index += 1
            continue
        titled = _TITLE.match(opened["rest"])
        raw_title = titled["title"] if titled is not None else opened["rest"]
        title = raw_title[1:-1] if raw_title[:1] in {"'", '"'} else raw_title
        quote = opened["quote"]
        body: list[str] = []
        index += 1
        while index < len(lines) and lines[index].strip() != quote:
            body.append(lines[index])
            index += 1
        ordinal += 1
        blocks.append(TestBlock(ordinal, opened["kind"], title, "\n".join(body)))
        index += 1
    return tuple(blocks)


def git_subcommands(body: str) -> frozenset[str]:
    """Every distinct git subcommand a test body invokes.

    Global options are skipped so `git -C dir status` counts as `status`, and a bare `git` with
    no subcommand counts as nothing.
    """
    found: set[str] = set()
    tokens = re.findall(r"[^\s;|&()<>]+", body)
    for position, token in enumerate(tokens):
        if token != "git":
            continue
        cursor = position + 1
        while cursor < len(tokens):
            candidate = tokens[cursor]
            if candidate in _VALUED_GLOBAL:
                cursor += 2
                continue
            if candidate.startswith("-"):
                cursor += 1
                continue
            break
        if cursor < len(tokens) and re.fullmatch(r"[a-z][a-z0-9-]*", tokens[cursor]):
            found.add(tokens[cursor])
    return frozenset(found)


def is_composition(body: str, minimum: int = COMPOSITION_MIN_DISTINCT) -> bool:
    """Whether a test body exercises at least ``minimum`` distinct git subcommands."""
    return len(git_subcommands(body)) >= minimum


def changed_scripts(source: Path, old_tag: str, new_tag: str) -> frozenset[str]:
    """The t/ scripts git's own history changed between two tags."""
    done = subprocess.run(
        ["git", "-C", str(source), "log", "--name-only", "--pretty=format:", f"{old_tag}..{new_tag}", "--", "t/"],
        capture_output=True,
        text=True,
        errors="replace",
        check=True,
        timeout=300,
    )
    return frozenset(
        Path(line).name
        for line in done.stdout.splitlines()
        if line.startswith("t/") and line.endswith(".sh")
    )


def run_script(
    script: str,
    binary_dir: Path,
    source: Path,
    *,
    timeout: int,
    env: Mapping[str, str] | None = None,
) -> ScriptRun:
    """Run one test script against the binary in ``binary_dir`` through GIT_TEST_INSTALLED."""
    environment = {**(env or {}), "GIT_TEST_INSTALLED": str(binary_dir)}
    try:
        done = subprocess.run(
            [f"./{script}"],
            cwd=source / "t",
            env=dict(environment),
            capture_output=True,
            text=True,
            # Required, not sloppy: git's suite emits non-UTF-8 bytes on purpose, and strict
            # decoding raises out of the grading loop and writes no reward at all. TAP is ASCII.
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        text = (expired.stdout or "") if isinstance(expired.stdout, str) else ""
        cases, bailed, plan = parse_tap(text)
        return ScriptRun(script, cases, bailed, plan, exit_code=124, timed_out=True)
    except OSError:
        # Deliberately swallowed: an unrunnable script is an aborted run, not an absent score.
        # Escaping here would write no reward, which Harbor reads as infrastructure error.
        return ScriptRun(script, (), bailed=True, plan=None, exit_code=127)
    cases, bailed, plan = parse_tap(done.stdout)
    return ScriptRun(script, cases, bailed, plan, exit_code=done.returncode)


def select_graded(
    reference: Mapping[str, ScriptRun],
    nop: Mapping[str, ScriptRun],
    oracle: Mapping[str, ScriptRun],
) -> dict[str, frozenset[int]]:
    """``O & R - N`` per script, over scripts whose reference run reported a complete plan."""
    graded: dict[str, frozenset[int]] = {}
    for script, reference_run in reference.items():
        if not reference_run.usable:
            continue
        oracle_run = oracle.get(script)
        if oracle_run is None:
            continue
        keep = oracle_run.passed_numbers() & reference_run.passed_numbers()
        nop_run = nop.get(script)
        if nop_run is not None:
            keep -= nop_run.passed_numbers()
        if keep:
            graded[script] = frozenset(keep)
    return graded


def build_manifest(
    graded: Mapping[str, frozenset[int]],
    blocks: Mapping[str, Sequence[TestBlock]],
    drifted: Iterable[str],
) -> tuple[GradedCase, ...]:
    """The frozen case list with both labels applied."""
    drift_set = frozenset(drifted)
    cases: list[GradedCase] = []
    for script in sorted(graded):
        by_ordinal = {block.ordinal: block for block in blocks.get(script, ())}
        for number in sorted(graded[script]):
            block = by_ordinal.get(number)
            cases.append(
                GradedCase(
                    script=script,
                    number=number,
                    title=block.title if block is not None else "",
                    drift=script in drift_set,
                    composition=is_composition(block.body) if block is not None else False,
                )
            )
    return tuple(cases)


def manifest_document(cases: Sequence[GradedCase], **pins: object) -> dict[str, object]:
    """The manifest as it freezes on disk."""
    return {
        "schema": SCHEMA,
        "drift_factor": DRIFT_FACTOR,
        "composition_factor": COMPOSITION_FACTOR,
        "composition_min_distinct": COMPOSITION_MIN_DISTINCT,
        "total_weight": sum(case.weight for case in cases),
        "case_count": len(cases),
        **pins,
        "cases": [case.document() for case in cases],
    }


@dataclass(frozen=True, slots=True)
class Score:
    """One candidate's reward over a frozen manifest."""

    total: float
    passed_weight: int
    total_weight: int
    per_family: dict[str, float] = field(default_factory=dict)

    def reward_document(self) -> dict[str, float | int]:
        # Harbor rejects a reward file holding any non-number, a nested dict included, so
        # per_family travels in report.json instead.
        if not 0.0 <= self.total <= 1.0:
            raise ValueError(f"reward outside [0, 1]: {self.total}")
        return {
            "reward": self.total,
            "passed_weight": self.passed_weight,
            "total_weight": self.total_weight,
        }

    def report_document(self) -> dict[str, object]:
        return {**self.reward_document(), "per_family": self.per_family}


def score(cases: Sequence[GradedCase], runs: Mapping[str, ScriptRun]) -> Score:
    """Weighted share of the frozen manifest the candidate passed.

    The denominator is the manifest, never the cases that executed, so a candidate whose run
    aborts a script cannot shrink what it is measured against. A script with no run, an aborted
    run, or a run that timed out passes none of its cases.
    """
    # Holistic variant. A test script earns its weight only when the candidate passes at least
    # SCRIPT_COMPLETENESS of that script's graded cases, because a command that works in the
    # common case and breaks on its flags, error paths or output format is not a working command.
    # Scattered passing cases across many half-built commands now earn nothing. The frozen oracle
    # still scores exactly 1.0, since it passes every graded case of every script by construction.
    script_total: dict[str, int] = {}
    script_passed: dict[str, int] = {}
    for case in cases:
        script_total[case.script] = script_total.get(case.script, 0) + case.weight
        run = runs.get(case.script)
        if run is not None and case.number in run.passed_numbers():
            script_passed[case.script] = script_passed.get(case.script, 0) + case.weight

    passed = 0
    total = 0
    family_passed: dict[str, int] = {}
    family_total: dict[str, int] = {}
    for script, weight in script_total.items():
        family = script.split("-", 1)[0]
        total += weight
        family_total[family] = family_total.get(family, 0) + weight
        share = script_passed.get(script, 0) / weight if weight else 0.0
        if share >= SCRIPT_COMPLETENESS:
            passed += weight
            family_passed[family] = family_passed.get(family, 0) + weight
    per_family = {
        name: round(family_passed.get(name, 0) / weight, 6)
        for name, weight in sorted(family_total.items())
        if weight
    }
    return Score(
        total=(passed / total) if total else 0.0,
        passed_weight=passed,
        total_weight=total,
        per_family=per_family,
    )


def write_reward(path: Path, result: Score) -> None:
    """Write the Harbor reward document, and the full report beside it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result.reward_document(), sort_keys=True) + "\n", encoding="utf-8")
    path.with_name("report.json").write_text(
        json.dumps(result.report_document(), sort_keys=True) + "\n", encoding="utf-8"
    )
    path.with_name("reward.txt").write_text(f"{result.total}\n", encoding="utf-8")
