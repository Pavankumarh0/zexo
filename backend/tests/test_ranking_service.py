"""Unit tests for discovery ranking and cursor pagination (stdlib only)."""

import unittest

from app.services.pagination import decode_cursor, encode_cursor
from app.services.ranking_service import (
    Candidate,
    compute_score,
    distance_score,
    rank,
    shared_tags,
    tag_overlap,
)


class TestDistanceScore(unittest.TestCase):
    def test_origin_is_one(self):
        self.assertEqual(distance_score(0, 5000), 1.0)

    def test_edge_is_zero(self):
        self.assertEqual(distance_score(5000, 5000), 0.0)

    def test_beyond_edge_clamped(self):
        self.assertEqual(distance_score(9000, 5000), 0.0)

    def test_midpoint(self):
        self.assertAlmostEqual(distance_score(2500, 5000), 0.5)


class TestTagOverlap(unittest.TestCase):
    def test_identical(self):
        self.assertEqual(tag_overlap(["a", "b"], ["a", "b"]), 1.0)

    def test_disjoint(self):
        self.assertEqual(tag_overlap(["a"], ["b"]), 0.0)

    def test_partial_jaccard(self):
        # intersection {a} = 1, union {a,b,c} = 3 -> 1/3
        self.assertAlmostEqual(tag_overlap(["a", "b"], ["a", "c"]), 1 / 3)

    def test_both_empty(self):
        self.assertEqual(tag_overlap([], []), 0.0)

    def test_shared_tags_sorted(self):
        self.assertEqual(shared_tags(["jazz", "film"], ["film", "jazz", "x"]), ("film", "jazz"))


class TestComputeScore(unittest.TestCase):
    def test_dual_factor_both_contribute(self):
        # Same distance, more tag overlap -> strictly higher score.
        near_no_tags = compute_score(100, 5000, ["a"], ["z"])
        near_tags = compute_score(100, 5000, ["a", "b"], ["a", "b"])
        self.assertGreater(near_tags, near_no_tags)

    def test_distance_matters_with_equal_tags(self):
        closer = compute_score(100, 5000, ["a"], ["a"])
        farther = compute_score(4000, 5000, ["a"], ["a"])
        self.assertGreater(closer, farther)

    def test_zero_weight_rejected(self):
        with self.assertRaises(ValueError):
            compute_score(100, 5000, ["a"], ["a"], w_distance=0.0, w_tag=1.0)
        with self.assertRaises(ValueError):
            compute_score(100, 5000, ["a"], ["a"], w_distance=1.0, w_tag=0.0)

    def test_default_weights_sum_expected(self):
        # Perfect on both axes -> w_distance + w_tag = 1.0 with defaults.
        self.assertAlmostEqual(compute_score(0, 5000, ["a"], ["a"]), 1.0)


class TestRank(unittest.TestCase):
    def test_orders_by_score_then_distance(self):
        user_tags = ["jazz", "film"]
        candidates = [
            Candidate("far_match", 4000, frozenset({"jazz", "film"})),
            Candidate("near_nomatch", 200, frozenset({"sports"})),
            Candidate("near_match", 300, frozenset({"jazz"})),
        ]
        ranked = rank(user_tags, candidates, radius_m=5000)
        ids = [r.user_id for r in ranked]
        # near_match wins (close + shared tag); ordering is deterministic.
        self.assertEqual(ids[0], "near_match")
        self.assertEqual(set(ids), {"far_match", "near_nomatch", "near_match"})

    def test_tie_break_is_stable(self):
        user_tags = ["a"]
        candidates = [
            Candidate("b", 100, frozenset({"a"})),
            Candidate("a", 100, frozenset({"a"})),
        ]
        ranked = rank(user_tags, candidates, radius_m=1000)
        # Equal score & distance -> tie-break by id ascending.
        self.assertEqual([r.user_id for r in ranked], ["a", "b"])

    def test_shared_tags_reported(self):
        ranked = rank(["jazz", "film"], [Candidate("x", 100, frozenset({"jazz"}))], 5000)
        self.assertEqual(ranked[0].shared_tags, ("jazz",))


class TestCursor(unittest.TestCase):
    def test_round_trip(self):
        payload = {"score": 0.873, "id": "abc-123"}
        cursor = encode_cursor(payload)
        self.assertEqual(decode_cursor(cursor), payload)

    def test_opaque_not_plaintext(self):
        cursor = encode_cursor({"id": "secret"})
        self.assertNotIn("secret", cursor)

    def test_invalid_returns_none(self):
        self.assertIsNone(decode_cursor("not-a-valid-cursor!!"))
        self.assertIsNone(decode_cursor(None))
        self.assertIsNone(decode_cursor(""))


if __name__ == "__main__":
    unittest.main()
