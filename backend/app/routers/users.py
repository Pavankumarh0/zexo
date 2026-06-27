"""User profile, location, visibility, blocking, and account deletion endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, status

from app.core.config import Settings, get_settings
from app.core.db import acquire
from app.core.errors import api_error
from app.core.security import get_current_user_id
from app.repositories import users_repo
from app.schemas.users import (
    BlockRequest,
    BlockResponse,
    LocationUpdateRequest,
    LocationUpdateResponse,
    PublicUserProfile,
    UpdateProfileRequest,
    UserProfile,
    VisibilityRequest,
    VisibilityResponse,
)
from app.services.location_service import fuzz_coordinates
from app.services.moderation import forward_report

router = APIRouter(prefix="/users", tags=["users"])


def _profile_from_row(row) -> UserProfile:
    return UserProfile(
        id=str(row["id"]),
        display_name=row["display_name"],
        bio=row["bio"],
        avatar_url=row["avatar_url"],
        interest_tags=list(row["interest_tags"] or []),
        is_visible=row["is_visible"],
        radius_m=row["radius_m"],
    )


@router.get("/me", response_model=UserProfile)
async def get_me(user_id: str = Depends(get_current_user_id)) -> UserProfile:
    async with acquire(user_id) as conn:
        row = await users_repo.get_profile(conn, user_id)
    if row is None:
        raise api_error(404, "not_found", "User not found")
    return _profile_from_row(row)


@router.put("/me", response_model=UserProfile)
async def update_me(
    body: UpdateProfileRequest,
    user_id: str = Depends(get_current_user_id),
) -> UserProfile:
    async with acquire(user_id) as conn:
        row = await users_repo.update_profile(
            conn,
            user_id,
            display_name=body.display_name,
            bio=body.bio,
            avatar_url=body.avatar_url,
            interest_tags=body.interest_tags,
            radius_m=body.radius_m,
        )
    if row is None:
        raise api_error(404, "not_found", "User not found")
    return _profile_from_row(row)


@router.put("/location", response_model=LocationUpdateResponse)
async def update_location(
    body: LocationUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    settings: Settings = Depends(get_settings),
) -> LocationUpdateResponse:
    """Apply ±150m server-side fuzzing, then persist ONLY the fuzzed point.

    The raw coordinates from the request are used solely to compute the fuzzed point and
    are never stored (Requirement 3 / location.hook.kiro).
    """
    fuzzed = fuzz_coordinates(body.lat, body.lng, fuzz_m=settings.location_fuzz_meters)
    async with acquire(user_id) as conn:
        row = await users_repo.upsert_fuzzy_location(
            conn,
            user_id,
            fuzzy_lat=fuzzed.lat,
            fuzzy_lng=fuzzed.lng,
            accuracy_m=body.accuracy_m,
        )
    return LocationUpdateResponse(
        updated_at=row["updated_at"],
        fuzzy_lat=row["fuzzy_lat"],
        fuzzy_lng=row["fuzzy_lng"],
    )


@router.put("/visibility", response_model=VisibilityResponse)
async def update_visibility(
    body: VisibilityRequest,
    user_id: str = Depends(get_current_user_id),
) -> VisibilityResponse:
    async with acquire(user_id) as conn:
        is_visible = await users_repo.set_visibility(conn, user_id, body.is_visible)
    return VisibilityResponse(is_visible=is_visible)


@router.get("/{other_id}", response_model=PublicUserProfile)
async def get_public_profile(
    other_id: str,
    user_id: str = Depends(get_current_user_id),
) -> PublicUserProfile:
    async with acquire(user_id) as conn:
        row = await users_repo.get_public_profile(conn, other_id)
    if row is None:
        raise api_error(404, "not_found", "User not found")
    return PublicUserProfile(
        id=str(row["id"]),
        display_name=row["display_name"],
        bio=row["bio"],
        avatar_url=row["avatar_url"],
        interest_tags=list(row["interest_tags"] or []),
    )


@router.post("/{other_id}/block", response_model=BlockResponse)
async def block_user(
    other_id: str,
    body: BlockRequest,
    user_id: str = Depends(get_current_user_id),
) -> BlockResponse:
    if other_id == user_id:
        raise api_error(422, "invalid", "Cannot block yourself")
    async with acquire(user_id) as conn:
        await users_repo.add_block(
            conn, user_id, other_id, reason=body.reason, reported=body.report
        )
    if body.report:
        await forward_report(reporter_id=user_id, reported_id=other_id, reason=body.reason)
    return BlockResponse(blocked=True)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(user_id: str = Depends(get_current_user_id)) -> None:
    """GDPR erasure (Requirement 17). Auth credentials are revoked via Supabase separately."""
    async with acquire(user_id) as conn:
        await users_repo.delete_account(conn, user_id)
