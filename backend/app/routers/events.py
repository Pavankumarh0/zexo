"""Event creation, discovery, detail, RSVP, attendees, and co-host endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.core.config import Settings, get_settings
from app.core.db import acquire
from app.core.errors import api_error
from app.core.security import get_current_user_id
from app.repositories import events_repo, users_repo
from app.schemas.events import (
    Attendee,
    AttendeeList,
    CreateEventRequest,
    EventDetail,
    EventList,
    RsvpRequest,
    RsvpResponse,
    UpdateEventRequest,
)
from app.services.location_service import clamp_radius
from app.services.pagination import decode_cursor, encode_cursor

router = APIRouter(prefix="/events", tags=["events"])

_HOST_ROLES = {"host", "co-host"}


def _event_detail(row, *, distance_m=None, my_rsvp=None) -> EventDetail:
    keys = row.keys()
    if distance_m is None and "distance_m" in keys and row["distance_m"] is not None:
        distance_m = row["distance_m"]
    if my_rsvp is None and "my_rsvp" in keys:
        my_rsvp = row["my_rsvp"]
    return EventDetail(
        id=str(row["id"]),
        creator_id=str(row["creator_id"]),
        title=row["title"],
        description=row["description"],
        lat=row["lat"],
        lng=row["lng"],
        radius_m=row["radius_m"],
        capacity=row["capacity"],
        tags=list(row["tags"] or []),
        visibility=row["visibility"],
        starts_at=row["starts_at"],
        ends_at=row["ends_at"],
        is_archived=row["is_archived"],
        attendee_count=row["attendee_count"] if "attendee_count" in keys else 0,
        distance_m=round(distance_m, 1) if distance_m is not None else None,
        my_rsvp=my_rsvp,
    )


@router.post("", response_model=EventDetail, status_code=201)
async def create_event(
    body: CreateEventRequest,
    user_id: str = Depends(get_current_user_id),
) -> EventDetail:
    async with acquire(user_id) as conn:
        row = await events_repo.create_event(
            conn, user_id,
            title=body.title, description=body.description,
            lat=body.lat, lng=body.lng, radius_m=body.radius_m,
            capacity=body.capacity, tags=body.tags, visibility=body.visibility,
            starts_at=body.starts_at, ends_at=body.ends_at,
        )
    detail = _event_detail(row, my_rsvp="going")
    detail.attendee_count = 1
    return detail


@router.get("", response_model=EventList)
async def list_events(
    user_id: str = Depends(get_current_user_id),
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius: float | None = Query(default=None),
    tags: list[str] | None = Query(default=None),
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
    settings: Settings = Depends(get_settings),
) -> EventList:
    radius_m = clamp_radius(
        radius, min_m=settings.radius_min_m, max_m=settings.radius_max_m,
        default_m=settings.radius_default_m,
    )
    cur = decode_cursor(cursor)
    after_distance = cur.get("distance_m") if cur else None
    after_id = cur.get("id") if cur else None

    async with acquire(user_id) as conn:
        rows = await events_repo.list_nearby(
            conn, user_id, lat=lat, lng=lng, radius_m=radius_m, tags=tags,
            after_distance=after_distance, after_id=after_id, limit=limit,
        )

    items = [_event_detail(r) for r in rows]
    next_cursor = (
        encode_cursor({"distance_m": rows[-1]["distance_m"], "id": str(rows[-1]["id"])})
        if len(rows) == limit
        else None
    )
    return EventList(items=items, next_cursor=next_cursor)


@router.get("/{event_id}", response_model=EventDetail)
async def get_event(event_id: str, user_id: str = Depends(get_current_user_id)) -> EventDetail:
    async with acquire(user_id) as conn:
        row = await events_repo.get_event(conn, event_id, user_id)
    if row is None:
        raise api_error(404, "not_found", "Event not found")
    return _event_detail(row)


@router.put("/{event_id}", response_model=EventDetail)
async def update_event(
    event_id: str,
    body: UpdateEventRequest,
    user_id: str = Depends(get_current_user_id),
) -> EventDetail:
    async with acquire(user_id) as conn:
        role = await events_repo.role_for(conn, event_id, user_id)
        if role not in _HOST_ROLES:
            raise api_error(403, "forbidden", "Host only")
        fields = body.model_dump(exclude_none=True)
        row = await events_repo.update_event(conn, event_id, fields)
        if row is None:
            raise api_error(404, "not_found", "Event not found")
        full = await events_repo.get_event(conn, event_id, user_id)
    return _event_detail(full)


@router.post("/{event_id}/rsvp", response_model=RsvpResponse)
async def rsvp(
    event_id: str,
    body: RsvpRequest,
    user_id: str = Depends(get_current_user_id),
) -> RsvpResponse:
    async with acquire(user_id) as conn:
        if body.status == "going":
            capacity = await events_repo.event_capacity(conn, event_id)
            if capacity is not None:
                others = await events_repo.going_count_excluding(conn, event_id, user_id)
                if others >= capacity:
                    raise api_error(409, "at_capacity", "Event is full")
        row = await events_repo.upsert_rsvp(conn, event_id, user_id, body.status)
    return RsvpResponse(event_id=str(row["event_id"]), status=row["status"], role=row["role"])


@router.get("/{event_id}/attendees", response_model=AttendeeList)
async def attendees(event_id: str, user_id: str = Depends(get_current_user_id)) -> AttendeeList:
    """Full attendee list only for host/co-host; others get the count only (Requirement 13.4)."""
    async with acquire(user_id) as conn:
        role = await events_repo.role_for(conn, event_id, user_id)
        count = await events_repo.attendee_count(conn, event_id)
        if role in _HOST_ROLES:
            rows = await events_repo.list_attendees(conn, event_id)
            attendee_list = [
                Attendee(
                    user_id=str(r["user_id"]), display_name=r["display_name"],
                    avatar_url=r["avatar_url"], role=r["role"], status=r["status"],
                )
                for r in rows
            ]
            return AttendeeList(event_id=event_id, attendee_count=count, attendees=attendee_list)
    return AttendeeList(event_id=event_id, attendee_count=count, attendees=None)


@router.post("/{event_id}/cohosts/{cohost_id}", status_code=204)
async def add_cohost(
    event_id: str,
    cohost_id: str,
    user_id: str = Depends(get_current_user_id),
) -> None:
    """Promote a user to co-host (host only). Accepts the deep-link invite flow's target."""
    async with acquire(user_id) as conn:
        role = await events_repo.role_for(conn, event_id, user_id)
        if role != "host":
            raise api_error(403, "forbidden", "Host only")
        await users_repo.get_public_profile(conn, cohost_id)  # 404 surfaces via FK if absent
        await events_repo.set_role(conn, event_id, cohost_id, "co-host")
