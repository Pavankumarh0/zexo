"""Unit tests for the privacy-critical location fuzzing math (stdlib only)."""

import math
import random
import unittest

from app.services.location_service import (
    DEFAULT_FUZZ_METERS,
    clamp_radius,
    fuzz_coordinates,
    haversine_m,
    offset_point,
)


class TestHaversine(unittest.TestCase):
    def test_zero_distance(self):
        self.assertAlmostEqual(haversine_m(37.0, -122.0, 37.0, -122.0), 0.0, places=6)

    def test_known_one_degree_latitude(self):
        # ~111.19 km per degree of latitude on the mean-radius sphere.
        d = haversine_m(0.0, 0.0, 1.0, 0.0)
        self.assertAlmostEqual(d, 111_194.0, delta=50.0)


class TestOffsetPoint(unittest.TestCase):
    def test_offset_distance_matches_request(self):
        # Projecting 150m then measuring back should recover ~150m for any bearing.
        for bearing in [0.0, math.pi / 2, math.pi, 3 * math.pi / 2]:
            lat2, lng2 = offset_point(37.7749, -122.4194, 150.0, bearing)
            back = haversine_m(37.7749, -122.4194, lat2, lng2)
            self.assertAlmostEqual(back, 150.0, delta=1.0)

    def test_longitude_wraps(self):
        # Near the antimeridian, longitude stays within [-180, 180).
        _, lng = offset_point(0.0, 179.9999, 150.0, math.pi / 2)
        self.assertTrue(-180.0 <= lng < 180.0)


class TestFuzzCoordinates(unittest.TestCase):
    def test_offset_within_jitter_band(self):
        rng = random.Random(1234)
        for _ in range(1000):
            fp = fuzz_coordinates(37.7749, -122.4194, fuzz_m=150.0, jitter=0.25, rng=rng)
            # Realised offset must lie within [112.5, 187.5] m.
            self.assertGreaterEqual(fp.offset_m, 112.5 - 1e-6)
            self.assertLessEqual(fp.offset_m, 187.5 + 1e-6)
            # And the actual geographic displacement matches the reported offset.
            actual = haversine_m(37.7749, -122.4194, fp.lat, fp.lng)
            self.assertAlmostEqual(actual, fp.offset_m, delta=1.0)

    def test_mean_offset_is_about_fuzz_radius(self):
        rng = random.Random(99)
        samples = [
            fuzz_coordinates(37.0, -122.0, fuzz_m=150.0, jitter=0.25, rng=rng).offset_m
            for _ in range(5000)
        ]
        mean = sum(samples) / len(samples)
        self.assertAlmostEqual(mean, DEFAULT_FUZZ_METERS, delta=5.0)

    def test_bearings_cover_full_circle(self):
        rng = random.Random(7)
        bearings = [fuzz_coordinates(10.0, 10.0, rng=rng).bearing_rad for _ in range(2000)]
        self.assertLess(min(bearings), 0.2)
        self.assertGreater(max(bearings), 2 * math.pi - 0.2)

    def test_original_point_is_not_returned(self):
        # Privacy: the fuzzed point must never equal the raw input.
        rng = random.Random(3)
        fp = fuzz_coordinates(40.0, -74.0, rng=rng)
        self.assertNotEqual((fp.lat, fp.lng), (40.0, -74.0))

    def test_invalid_params(self):
        with self.assertRaises(ValueError):
            fuzz_coordinates(0, 0, fuzz_m=0)
        with self.assertRaises(ValueError):
            fuzz_coordinates(0, 0, jitter=1.0)


class TestClampRadius(unittest.TestCase):
    def setUp(self):
        self.kw = dict(min_m=500, max_m=50000, default_m=5000)

    def test_none_returns_default(self):
        self.assertEqual(clamp_radius(None, **self.kw), 5000)

    def test_below_min(self):
        self.assertEqual(clamp_radius(100, **self.kw), 500)

    def test_above_max(self):
        self.assertEqual(clamp_radius(999999, **self.kw), 50000)

    def test_in_range(self):
        self.assertEqual(clamp_radius(2500, **self.kw), 2500)


if __name__ == "__main__":
    unittest.main()
