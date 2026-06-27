"""Discovery feed ranking.

Framework-independent (standard library only) so the ranking math can be unit-tested
directly. See design.md "Ranking Algorithm" and feed.hook.kiro.

Invariant (Requirement 5.2): the score MUST weight BOTH a distance component AND an
interest-tag-overlap component. Neither may be dropped or zero-weighted in normal operation.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass

DEFAULT_W_DISTANCE = 0.6
DEFAULT_W_TAG = 0.4


@dataclass(frozen=True)
class Candidate:
    """A discovery candidate to be scored."""

    user_id: str
    distance_m: float
    tags: frozenset[str]


@dataclass(frozen=True)
class ScoredCandidate:
    user_id: str
    distance_m: float
    score: float
    shared_tags: tuple[str, ...]


def distance_score(distance_m: float, radius_m: float) -> float:
    """1.0 at the origin, 0.0 at (or beyond) the radius edge. Clamped to [0, 1]."""
    if radius_m <= 0:
        return 0.0
    return max(0.0, min(1.0, 1.0 - (distance_m / radius_m)))


def tag_overlap(a: Iterable[str], b: Iterable[str]) -> float:
    """Jaccard similarity of two tag sets, in [0, 1]."""
    sa, sb = set(a), set(b)
    if not sa and not sb:
        return 0.0
    union = sa | sb
    if not union:
        return 0.0
    return len(sa & sb) / len(union)


def shared_tags(a: Iterable[str], b: Iterable[str]) -> tuple[str, ...]:
    """Tags present in both sets, returned in a stable (sorted) order."""
    return tuple(sorted(set(a) & set(b)))


def compute_score(
    distance_m: float,
    radius_m: float,
    user_tags: Iterable[str],
    candidate_tags: Iterable[str],
    *,
    w_distance: float = DEFAULT_W_DISTANCE,
    w_tag: float = DEFAULT_W_TAG,
) -> float:
    """Blend distance and tag-overlap scores. Both weights must be > 0 (dual-factor rule)."""
    if w_distance <= 0 or w_tag <= 0:
        raise ValueError("Both distance and tag weights must be positive (dual-factor ranking)")
    d = distance_score(distance_m, radius_m)
    t = tag_overlap(user_tags, candidate_tags)
    return (w_distance * d) + (w_tag * t)


def rank(
    user_tags: Iterable[str],
    candidates: Sequence[Candidate],
    radius_m: float,
    *,
    w_distance: float = DEFAULT_W_DISTANCE,
    w_tag: float = DEFAULT_W_TAG,
) -> list[ScoredCandidate]:
    """Score and order candidates by score DESC, then distance ASC, then id ASC (stable)."""
    user_tag_set = set(user_tags)
    scored = [
        ScoredCandidate(
            user_id=c.user_id,
            distance_m=c.distance_m,
            score=compute_score(
                c.distance_m, radius_m, user_tag_set, c.tags,
                w_distance=w_distance, w_tag=w_tag,
            ),
            shared_tags=shared_tags(user_tag_set, c.tags),
        )
        for c in candidates
    ]
    scored.sort(key=lambda s: (-s.score, s.distance_m, s.user_id))
    return scored
