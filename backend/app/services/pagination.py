"""Opaque cursor-based pagination helpers (stdlib only).

The discovery and events feeds use keyset/cursor pagination rather than offset pagination
(see conventions.md and feed.hook.kiro). A cursor encodes the sort key of the last item
returned so the next page can resume strictly after it.
"""

from __future__ import annotations

import base64
import binascii
import json
from typing import Any


def encode_cursor(payload: dict[str, Any]) -> str:
    """Encode a sort-key payload into a URL-safe opaque cursor."""
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii")


def decode_cursor(cursor: str | None) -> dict[str, Any] | None:
    """Decode an opaque cursor back into its payload, or None if absent/invalid."""
    if not cursor:
        return None
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii"))
        data = json.loads(raw)
    except (ValueError, binascii.Error, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None
