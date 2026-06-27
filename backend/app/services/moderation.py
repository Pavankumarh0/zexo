"""Content-moderation webhook stub (Requirement 16.3).

When a user files a report alongside a block, forward it to an external moderation system.
This is a stub: it logs the report and POSTs to a configured webhook if one is set.
"""

from __future__ import annotations

import logging

import httpx

from app.core.config import get_settings

logger = logging.getLogger("zexo.moderation")


async def forward_report(*, reporter_id: str, reported_id: str, reason: str | None) -> None:
    payload = {
        "reporter_id": reporter_id,
        "reported_id": reported_id,
        "reason": reason or "",
    }
    logger.info("moderation report filed: %s", payload)

    webhook_url = getattr(get_settings(), "moderation_webhook_url", "")
    if not webhook_url:
        # Stub mode: nothing configured, the log entry is the record of the report.
        return
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(webhook_url, json=payload)
    except httpx.HTTPError as exc:  # never block the user action on webhook failure
        logger.warning("moderation webhook failed: %s", exc)
