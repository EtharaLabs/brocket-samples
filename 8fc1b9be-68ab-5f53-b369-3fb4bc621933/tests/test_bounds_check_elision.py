#!/usr/bin/env python3
"""Pure checker tests: the bounds-assert pattern and the scored corpus (Bucket D).

These need no compiler and no submission. They hold the two things the grade depends on that a
compiler run would otherwise hide: that the pattern counts bounds checks and nothing else, and
that the scored corpus still means what it was measured to mean.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import count_bounds_checks as counter  # noqa: E402

CORPUS = HERE / "corpus"
EXPECTED = json.loads((CORPUS / "expected.json").read_text(encoding="utf-8"))

# As rustc emits it, from the optimized MIR of a slice index.
BOUNDS_LINE = (
    '        assert(move _6, "index out of bounds: the length is {} but the index is {}", '
    "copy _3, copy _5) -> [success: bb2, unwind continue];"
)
# An assert that is not a bounds check, and must never be counted as one.
OVERFLOW_LINE = (
    '        assert(!move _9, "attempt to add with overflow") -> [success: bb4, unwind continue];'
)


def test_pattern_matches_a_bounds_assert() -> None:
    assert counter.BOUNDS_ASSERT.findall(BOUNDS_LINE)


def test_pattern_rejects_a_non_bounds_assert() -> None:
    assert not counter.BOUNDS_ASSERT.findall(OVERFLOW_LINE)


def test_any_assert_counts_both_kinds() -> None:
    both = "%s\n%s" % (BOUNDS_LINE, OVERFLOW_LINE)
    assert len(counter.ANY_ASSERT.findall(both)) == 2


def test_every_scored_case_exists_on_disk() -> None:
    for group in ("must_keep", "should_remove"):
        for name in EXPECTED[group]:
            assert (CORPUS / group / name).is_file(), "%s/%s is scored but absent" % (group, name)


def test_every_baseline_is_positive() -> None:
    """A case whose baseline is zero can never be removed, so it would cap the reward below 1."""
    for group in ("must_keep", "should_remove"):
        for name, baseline in EXPECTED[group].items():
            assert baseline >= 1, "%s/%s has baseline %r" % (group, name, baseline)


def test_groups_are_disjoint() -> None:
    assert not set(EXPECTED["must_keep"]) & set(EXPECTED["should_remove"])


def test_unprovable_cases_are_not_scored() -> None:
    """A case no intraprocedural analysis can prove must not sit in the scored set.

    Both exclusions were found by reading the MIR rather than the Rust source: the index arrives
    from an opaque call, so the body holds no relation to prove the check redundant. Scoring one
    would put the full reward out of reach of any correct submission.
    """
    unprovable = CORPUS / "unprovable"
    if not unprovable.is_dir():
        return
    scored = set(EXPECTED["must_keep"]) | set(EXPECTED["should_remove"])
    for source in unprovable.glob("*.rs"):
        assert source.name not in scored, "%s is unprovable but scored" % source.name


def test_already_upstream_cases_are_not_scored() -> None:
    """Upstream already removes these, so a baseline of zero earns nothing and scores nothing."""
    upstream = CORPUS / "already_upstream"
    if not upstream.is_dir():
        return
    scored = set(EXPECTED["must_keep"]) | set(EXPECTED["should_remove"])
    for source in upstream.glob("*.rs"):
        assert source.name not in scored, "%s is already upstream but scored" % source.name


def test_corpus_holds_no_unscored_stragglers() -> None:
    """Every case under a scored group is scored, so a file cannot be added and silently ignored."""
    for group in ("must_keep", "should_remove"):
        on_disk = {source.name for source in (CORPUS / group).glob("*.rs")}
        assert on_disk == set(EXPECTED[group]), "%s: %r" % (
            group,
            on_disk.symmetric_difference(EXPECTED[group]),
        )


def test_the_pinned_commit_is_recorded() -> None:
    """The baselines are only meaningful against the compiler they were measured on."""
    commit = EXPECTED.get("rustc_commit")
    assert isinstance(commit, str) and len(commit) == 40
