"""Authentication request/response schemas."""

from __future__ import annotations

from pydantic import BaseModel, Field


class VerifyOtpRequest(BaseModel):
    phone: str = Field(min_length=5, max_length=20)
    otp: str = Field(min_length=4, max_length=10)


class GoogleAuthRequest(BaseModel):
    id_token: str


class AuthUser(BaseModel):
    id: str
    display_name: str | None = None
    is_new: bool = False


class AuthResponse(BaseModel):
    jwt: str
    user: AuthUser
