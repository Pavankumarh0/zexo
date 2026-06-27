"""Discovery feed (ranked cards) and map bounding-box endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.core.config import Settings, get_settings
from app.core.db import acquire
from app.core.errors import api_error
from app.core.security import get_current_user_id
from app.repositories import discover_repo, users_repo
from app.schemas.discover import (
    DiscoverFeed,
    DiscoverItem,
    MapEvent,
    MapResponse,
    MapUser,
)
from app.schemas.users import PublicUserProfile
from app.services.location_service import clamp_radius
from app.services.pagination import decode_cursor, encode_cursor
from app.services.ranking_service import Candidate, rank

router = APIRouter(prefix="/discover", tags=["discover"])


@router.get("", response_model=DiscoverFeed)
async def discover_feed(
    user_id: str = Depends(get_current_user_id),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    radius: float | None = Query(default=None),
    tags: list[str] | None = Query(default=None),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
    settings: Settings = Depends(get_settings),
) -> DiscoverFeed:
    """Ranked nearby-user feed: distance x tag-overlap, cursor-paginated, excludes
    invisible/blocked users (handled by the nearby_users SECURITY DEFINER function)."""
    radius_m = clamp_radius(
        radius, min_m=settings.radius_min_m, max_m=settings.radius_max_m,
        default_m=settings.radius_default_m,
    )

    async with acquire(user_id) as conn:
        me = await users_repo.get_profile(conn, user_id)
        if me is None:
            raise api_error(404, "not_found", "User not found")

        # Use supplied coordinates, else fall back to the caller's stored fuzzy origin.
        if lat is None or lng is None:
            origin = await users_repo.get_origin_and_radius(conn, user_id)
            if origin is None or origin["lat"] is None:
                return DiscoverFeed(items=[], next_cursor=None)
            lat, lng = origin["lat"], origin["lng"]

        rows = await discover_repo.nearby_users(conn, user_id, lat=lat, lng=lng, radius_m=radius_m)

    my_tags = list(me["interest_tags"] or [])
    candidates = [
        Candidate(
            user_id=str(r["user_id"]),
            distance_m=r["distance_m"],
            tags=frozenset(r["interest_tags"] or []),
        )
        for r in rows
    ]
    by_id = {str(r["user_id"]): r for r in rows}

    ranked = rank(
        my_tags, candidates, radius_m,
        w_distance=settings.discover_weight_distance,
        w_tag=settings.discover_weight_tag,
    )

    # Cursor encodes (score, id) of the last item; resume strictly after it.
    cur = decode_cursor(cursor)
    if cur is not None:
        after = (cur.get("score"), cur.get("id"))
        ranked = [s for s in ranked if (-s.score, s.user_id) > (-after[0], after[1])]

    page = ranked[:limit]
    items = [
        DiscoverItem(
            user=PublicUserProfile(
                id=s.user_id,
                display_name=by_id[s.user_id]["display_name"],
                avatar_url=by_id[s.user_id]["avatar_url"],
                interest_tags=list(by_id[s.user_id]["interest_tags"] or []),
            ),
            distance_m=round(s.distance_m, 1),
            shared_tags=list(s.shared_tags),
            score=round(s.score, 6),
        )
        for s in page
    ]
    next_cursor = (
        encode_cursor({"score": page[-1].score, "id": page[-1].user_id})
        if len(page) == limit and len(ranked) > limit
        else None
    )
    return DiscoverFeed(items=items, next_cursor=next_cursor)


@router.get("/map", response_model=MapResponse)
async def discover_map(
    bbox: str = Query(..., description="minLng,minLat,maxLng,maxLat"),
    user_id: str = Depends(get_current_user_id),
) -> MapResponse:
    try:
        min_lng, min_lat, max_lng, max_lat = (float(x) for x in bbox.split(","))
    except ValueError as exc:
        raise api_error(
            422, "invalid_bbox", "bbox must be 'minLng,minLat,maxLng,maxLat'"
        ) from exc

    async with acquire(user_id) as conn:
        user_rows = await discover_repo.map_users(
            conn, user_id, min_lng=min_lng, min_lat=min_lat, max_lng=max_lng, max_lat=max_lat
        )
        event_rows = await discover_repo.map_events(
            conn, user_id, min_lng=min_lng, min_lat=min_lat, max_lng=max_lng, max_lat=max_lat
        )

    return MapResponse(
        users=[
            MapUser(id=str(r["user_id"]), fuzzy_lat=r["fuzzy_lat"], fuzzy_lng=r["fuzzy_lng"])
            for r in user_rows
        ],
        events=[
            MapEvent(
                id=str(r["id"]),
                title=r["title"],
                lat=r["lat"],
                lng=r["lng"],
                tags=list(r["tags"] or []),
            )
            for r in event_rows
        ],
    )
