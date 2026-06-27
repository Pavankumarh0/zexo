"""Authentication endpoints.

Zexo uses Supabase Auth with **Google OAuth only** (steering: stack.md). The client
performs the native Google Sign-In, then sends the resulting ID token here; we exchange it
with Supabase GoTrue and ensure a corresponding row exists in our `users` table. We never
issue our own tokens or store passwords.
"""

from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.core.db import acquire_service
from app.core.errors import api_error
from app.schemas.auth import AuthResponse, AuthUser, GoogleAuthRequest

router = APIRouter(prefix="/auth", tags=["auth"])


async def _ensure_user_row(user_id: str, *, email: str | None) -> bool:
    """Upsert a users row for an authenticated identity. Returns True if newly created."""
    async with acquire_service() as conn:
        existing = await conn.fetchval("SELECT 1 FROM users WHERE id = $1", user_id)
        if existing:
            await conn.execute("UPDATE users SET last_seen_at = now() WHERE id = $1", user_id)
            return False
        await conn.execute(
            """
            INSERT INTO users (id, email, last_seen_at)
            VALUES ($1, $2, now())
            ON CONFLICT (id) DO NOTHING
            """,
            user_id,
            email,
        )
        return True


async def _gotrue(path: str, payload: dict, settings: Settings) -> dict:
    if not settings.supabase_url:
        raise api_error(503, "auth_unconfigured", "Supabase not configured")
    url = f"{settings.supabase_url}/auth/v1{path}"
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Content-Type": "application/json",
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(url, json=payload, headers=headers)
    if resp.status_code >= 400:
        raise api_error(401, "auth_failed", "Google verification failed")
    return resp.json()


def _build_response(data: dict, *, created: bool) -> AuthResponse:
    token = data.get("access_token") or data.get("token")
    user = data.get("user", {}) or {}
    if not token:
        raise api_error(401, "auth_failed", "No token returned")
    return AuthResponse(
        jwt=token,
        user=AuthUser(
            id=str(user.get("id")),
            display_name=(user.get("user_metadata") or {}).get("display_name"),
            email=user.get("email"),
            is_new=created,
        ),
    )


@router.post("/google", response_model=AuthResponse)
async def google_auth(
    body: GoogleAuthRequest, settings: Settings = Depends(get_settings)
) -> AuthResponse:
    """Exchange a Google ID token for a Supabase session."""
    payload: dict = {"provider": "google", "id_token": body.id_token}
    if body.access_token:
        payload["access_token"] = body.access_token
    data = await _gotrue("/token?grant_type=id_token", payload, settings)
    user = data.get("user", {}) or {}
    created = await _ensure_user_row(str(user.get("id")), email=user.get("email"))
    return _build_response(data, created=created)
