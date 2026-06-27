"""Location privacy & geospatial helpers.

This module is intentionally framework-independent (standard library only) so the
privacy-critical fuzzing math can be unit-tested without a database or web server.

Privacy invariant (Requirement 3 / location.hook.kiro):
    Raw GPS coordinates are offset by ~150m in a random direction *before* anything is
    persisted. Only the fuzzed point may ever be stored, queried, or returned. The caller
    must never persist or expose the original coordinates beyond the transient `geom`
    column used at insert time.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass

# Mean Earth radius in metres (WGS84 sphere approximation), adequate for ~150m offsets.
EARTH_RADIUS_M = 6_371_008.8

# Default fuzz radius and jitter band. The realised offset lies in
# [FUZZ_METERS * (1 - JITTER), FUZZ_METERS * (1 + JITTER)].
DEFAULT_FUZZ_METERS = 150.0
DEFAULT_JITTER = 0.25


@dataclass(frozen=True)
class FuzzedPoint:
    """Result of fuzzing a coordinate. `offset_m` and `bearing_rad` are returned for
    test/observability purposes only and must not be persisted."""

    lat: float
    lng: float
    offset_m: float
    bearing_rad: float


def _clamp_lat(lat: float) -> float:
    return max(-90.0, min(90.0, lat))


def _wrap_lng(lng: float) -> float:
    # Normalise longitude into [-180, 180).
    return ((lng + 180.0) % 360.0) - 180.0


def offset_point(
    lat: float, lng: float, distance_m: float, bearing_rad: float
) -> tuple[float, float]:
    """Project a point a given distance along a bearing on a sphere (forward geodesic).

    Returns the destination (lat, lng) in degrees.
    """
    ang = distance_m / EARTH_RADIUS_M
    lat1 = math.radians(lat)
    lng1 = math.radians(lng)

    sin_lat1 = math.sin(lat1)
    cos_lat1 = math.cos(lat1)
    sin_ang = math.sin(ang)
    cos_ang = math.cos(ang)

    sin_lat2 = sin_lat1 * cos_ang + cos_lat1 * sin_ang * math.cos(bearing_rad)
    lat2 = math.asin(max(-1.0, min(1.0, sin_lat2)))

    y = math.sin(bearing_rad) * sin_ang * cos_lat1
    x = cos_ang - sin_lat1 * math.sin(lat2)
    lng2 = lng1 + math.atan2(y, x)

    return _clamp_lat(math.degrees(lat2)), _wrap_lng(math.degrees(lng2))


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two points in metres."""
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def fuzz_coordinates(
    lat: float,
    lng: float,
    *,
    fuzz_m: float = DEFAULT_FUZZ_METERS,
    jitter: float = DEFAULT_JITTER,
    rng: random.Random | None = None,
) -> FuzzedPoint:
    """Offset a coordinate by ~`fuzz_m` metres in a uniformly random direction.

    The realised offset distance is drawn uniformly from
    [fuzz_m * (1 - jitter), fuzz_m * (1 + jitter)] so the fuzz magnitude itself is not a
    constant that could be trivially subtracted out.

    `rng` may be injected for deterministic testing; otherwise a module-level RNG is used.
    """
    if fuzz_m <= 0:
        raise ValueError("fuzz_m must be positive")
    if not 0.0 <= jitter < 1.0:
        raise ValueError("jitter must be in [0, 1)")

    r = rng or _DEFAULT_RNG
    bearing = r.uniform(0.0, 2.0 * math.pi)
    low = fuzz_m * (1.0 - jitter)
    high = fuzz_m * (1.0 + jitter)
    distance = r.uniform(low, high)

    new_lat, new_lng = offset_point(lat, lng, distance, bearing)
    return FuzzedPoint(lat=new_lat, lng=new_lng, offset_m=distance, bearing_rad=bearing)


def clamp_radius(radius_m: float | None, *, min_m: float, max_m: float, default_m: float) -> float:
    """Clamp a requested discovery radius into the allowed band (Requirement 4.5 / 19.2)."""
    if radius_m is None:
        return default_m
    return max(min_m, min(max_m, float(radius_m)))


# Non-cryptographic RNG is acceptable here: fuzzing is a privacy obfuscation, not a secret.
_DEFAULT_RNG = random.Random()
