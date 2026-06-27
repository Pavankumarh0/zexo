"""Authentication: validate Supabase-issued JWTs and resolve the current user.

We do NOT issue our own tokens or store passwords (steering: stack.md — Supabase Auth only).
FastAPI endpoints depend on `get_current_user_id` to enforce auth and to feed the RLS
user context in app.core.db.
"""

from __future__ import annotations

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import get_settings

_bearer = HTTPBearer(auto_error=False)


class AuthError(HTTPException):
    def __init__(self, message: str = "Not authenticated") -> None:
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "unauthorized", "message": message}},
            headers={"WWW-Authenticate": "Bearer"},
        )


def decode_token(token: str) -> dict:
    """Validate signature + expiry of a Supabase JWT and return its claims."""
    settings = get_settings()
    if not settings.supabase_jwt_secret:
        raise AuthError("Auth is not configured")
    try:
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
            options={"require": ["exp", "sub"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise AuthError("Token expired") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthError("Invalid token") from exc


async def get_current_user_id(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    """FastAPI dependency: returns the authenticated user's UUID (the JWT `sub`)."""
    if creds is None or not creds.credentials:
        raise AuthError()
    claims = decode_token(creds.credentials)
    sub = claims.get("sub")
    if not sub:
        raise AuthError("Token missing subject")
    return str(sub)
