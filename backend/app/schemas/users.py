"""User, profile, location, and visibility schemas."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class UserProfile(BaseModel):
    id: str
    display_name: str | None = None
    bio: str | None = None
    avatar_url: str | None = None
    interest_tags: list[str] = Field(default_factory=list)
    is_visible: bool = True
    radius_m: float = 5000


class PublicUserProfile(BaseModel):
    """Profile fields safe to expose to other users — no phone/email/location."""

    id: str
    display_name: str | None = None
    bio: str | None = None
    avatar_url: str | None = None
    interest_tags: list[str] = Field(default_factory=list)


class UpdateProfileRequest(BaseModel):
    display_name: str | None = Field(default=None, max_length=80)
    bio: str | None = Field(default=None, max_length=500)
    avatar_url: str | None = None
    interest_tags: list[str] | None = None
    radius_m: float | None = Field(default=None, ge=500, le=50_000)

    @field_validator("interest_tags")
    @classmethod
    def max_ten_tags(cls, v: list[str] | None) -> list[str] | None:
        if v is not None and len(v) > 10:
            raise ValueError("A user may have at most 10 interest tags")
        return v


class LocationUpdateRequest(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    source: Literal["gps", "city"] = "gps"


class LocationUpdateResponse(BaseModel):
    """Only fuzzed coordinates are ever returned (Requirement 3.3)."""

    updated_at: datetime
    fuzzy_lat: float
    fuzzy_lng: float


class VisibilityRequest(BaseModel):
    is_visible: bool


class VisibilityResponse(BaseModel):
    is_visible: bool


class BlockRequest(BaseModel):
    report: bool = False
    reason: str | None = Field(default=None, max_length=500)


class BlockResponse(BaseModel):
    blocked: bool
