"""Authentication request/response schemas (Google OAuth only)."""

from __future__ import annotations

from pydantic import BaseModel


class GoogleAuthRequest(BaseModel):
    """A Google ID token obtained from the native Google Sign-In flow."""

    id_token: str
    access_token: str | None = None


class AuthUser(BaseModel):
    id: str
    display_name: str | None = None
    email: str | None = None
    is_new: bool = False


class AuthResponse(BaseModel):
    jwt: str
    user: AuthUser
