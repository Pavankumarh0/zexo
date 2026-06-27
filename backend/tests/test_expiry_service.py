"""Unit tests for thread range-expiry (Requirement 9.2)."""

import unittest

from app.services.expiry_service import is_out_of_range


class TestRangeExpiry(unittest.TestCase):
    # San Francisco reference point.
    LAT, LNG = 37.7749, -122.4194

    def test_in_range_not_expired(self):
        # ~150m away, well within a 5km radius.
        self.assertFalse(is_out_of_range(37.7762, -122.4194, self.LAT, self.LNG, 5000))

    def test_out_of_range_expires(self):
        # ~1.1km north, outside a 500m radius.
        self.assertTrue(is_out_of_range(37.7849, -122.4194, self.LAT, self.LNG, 500))

    def test_exactly_within_radius_boundary(self):
        # Same point => distance 0, never out of range.
        self.assertFalse(is_out_of_range(self.LAT, self.LNG, self.LAT, self.LNG, 500))


if __name__ == "__main__":
    unittest.main()
