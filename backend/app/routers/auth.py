"""Authentication endpoints.

Zexo uses Supabase Auth (steering: stack.md). These endpoints proxy verification to
Supabase GoTrue, then ensure a corresponding row exists in our `users` table. We never
issue our own tokens or store passwords.
"""

from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.core.db import acquire_service
from app.core.errors import api_error
from app.schemas.auth import AuthResponse, AuthUser, GoogleAuthRequest, VerifyOtpRequest

router = APIRouter(prefix="/auth", tags=["auth"])


async def _ensure_user_row(user_id: str, *, phone: str | None, email: str | None) -> bool:
    """Upsert a users row for an authenticated identity. Returns True if newly created."""
    async with acquire_service() as conn:
        existing = await conn.fetchval("SELECT 1 FROM users WHERE id = $1", user_id)
        if existing:
            await conn.execute("UPDATE users SET last_seen_at = now() WHERE id = $1", user_id)
            return False
        await conn.execute(
            """
            INSERT INTO users (id, phone, email, last_seen_at)
            VALUES ($1, $2, $3, now())
            ON CONFLICT (id) DO NOTHING
            """,
            user_id, phone, email,
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
        raise api_error(401, "auth_failed", "Verification failed")
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
            is_new=created,
        ),
    )


@router.post("/verify-otp", response_model=AuthResponse)
async def verify_otp(
    body: VerifyOtpRequest, settings: Settings = Depends(get_settings)
) -> AuthResponse:
    data = await _gotrue(
        "/verify", {"type": "sms", "phone": body.phone, "token": body.otp}, settings
    )
    user = data.get("user", {}) or {}
    created = await _ensure_user_row(
        str(user.get("id")), phone=user.get("phone"), email=user.get("email")
    )
    return _build_response(data, created=created)


@router.post("/google", response_model=AuthResponse)
async def google_auth(
    body: GoogleAuthRequest, settings: Settings = Depends(get_settings)
) -> AuthResponse:
    data = await _gotrue(
        "/token?grant_type=id_token",
        {"provider": "google", "id_token": body.id_token},
        settings,
    )
    user = data.get("user", {}) or {}
    created = await _ensure_user_row(
        str(user.get("id")), phone=user.get("phone"), email=user.get("email")
    )
    return _build_response(data, created=created)
