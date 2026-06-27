"""Thread expiry logic: dual model of 24h TTL OR range exit (Requirement 9.2).

`is_out_of_range` is pure (stdlib only) and unit-testable. The TTL half is enforced at the
database (messages.expires_at default) and the hourly purge job.
"""

from __future__ import annotations

from app.services.location_service import haversine_m


def is_out_of_range(
    sender_lat: float,
    sender_lng: float,
    peer_lat: float,
    peer_lng: float,
    peer_radius_m: float,
) -> bool:
    """True when the sender is beyond the peer's discovery radius, which expires the thread
    immediately (Requirement 9.2)."""
    distance = haversine_m(sender_lat, sender_lng, peer_lat, peer_lng)
    return distance > peer_radius_m
