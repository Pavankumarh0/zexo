"""Chat thread endpoints + real-time WebSocket message stream."""

from __future__ import annotations

import json
import logging

import sentry_sdk
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect

from app.core.db import acquire
from app.core.errors import api_error
from app.core.security import AuthError, decode_token, get_current_user_id
from app.repositories import threads_repo, users_repo
from app.schemas.chat import (
    ExpireResponse,
    Message,
    OpenThreadRequest,
    OpenThreadResponse,
    ThreadList,
    ThreadSummary,
)
from app.schemas.users import PublicUserProfile
from app.services.expiry_service import is_out_of_range
from app.services.ws_manager import manager

logger = logging.getLogger("zexo.threads")
router = APIRouter(prefix="/threads", tags=["threads"])


@router.post("", response_model=OpenThreadResponse, status_code=201)
async def open_thread(
    body: OpenThreadRequest,
    user_id: str = Depends(get_current_user_id),
) -> OpenThreadResponse:
    if body.peer_id == user_id:
        raise api_error(422, "invalid", "Cannot open a thread with yourself")
    async with acquire(user_id) as conn:
        thread_id, created = await threads_repo.open_or_get_thread(conn, user_id, body.peer_id)
    return OpenThreadResponse(thread_id=thread_id, created=created)


@router.get("", response_model=ThreadList)
async def list_threads(user_id: str = Depends(get_current_user_id)) -> ThreadList:
    async with acquire(user_id) as conn:
        rows = await threads_repo.list_threads(conn, user_id)
    items = [
        ThreadSummary(
            id=str(r["id"]),
            peer=PublicUserProfile(
                id=str(r["peer_id"]),
                display_name=r["peer_display_name"],
                avatar_url=r["peer_avatar_url"],
                bio=r["peer_bio"],
                interest_tags=list(r["peer_interest_tags"] or []),
            ),
            last_message_at=r["last_message_at"],
            unread_count=r["unread_count"],
            expires_at=r["expires_at"],
        )
        for r in rows
    ]
    return ThreadList(items=items)


@router.post("/{thread_id}/expire", response_model=ExpireResponse)
async def force_expire(
    thread_id: str, user_id: str = Depends(get_current_user_id)
) -> ExpireResponse:
    async with acquire(user_id) as conn:
        thread = await threads_repo.get_thread(conn, thread_id)
        if thread is None or user_id not in (str(thread["user_a"]), str(thread["user_b"])):
            raise api_error(404, "not_found", "Thread not found")
        await threads_repo.expire_thread(conn, thread_id)
    await manager.publish(thread_id, {"type": "thread_expired", "reason": "manual"})
    return ExpireResponse(expired=True, reason="manual")


async def _authenticate_ws(websocket: WebSocket) -> str:
    """Resolve the user from the `token` query param or Authorization header for the WS."""
    token = websocket.query_params.get("token")
    if not token:
        header = websocket.headers.get("authorization", "")
        if header.lower().startswith("bearer "):
            token = header[7:]
    if not token:
        raise AuthError("Missing token")
    claims = decode_token(token)
    sub = claims.get("sub")
    if not sub:
        raise AuthError("Token missing subject")
    return str(sub)


@router.websocket("/ws/thread/{thread_id}")
async def ws_thread(websocket: WebSocket, thread_id: str) -> None:
    """Real-time message stream. Frames: message | read | heartbeat (in);
    message | read_receipt | thread_expired (out). See design.md API contracts."""
    try:
        user_id = await _authenticate_ws(websocket)
    except AuthError:
        await websocket.close(code=4401)
        return

    # Authorise participation and load peer context for range-expiry checks.
    async with acquire(user_id) as conn:
        thread = await threads_repo.get_thread(conn, thread_id)
        if thread is None or user_id not in (str(thread["user_a"]), str(thread["user_b"])):
            await websocket.close(code=4403)
            return
        peer_id = (
            str(thread["user_b"])
            if str(thread["user_a"]) == user_id
            else str(thread["user_a"])
        )
        peer_origin = await users_repo.get_origin_and_radius(conn, peer_id)

    await manager.connect(thread_id, websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                frame = json.loads(raw)
            except json.JSONDecodeError:
                continue
            await _handle_frame(frame, thread_id, user_id, peer_origin, websocket)
    except WebSocketDisconnect:
        pass
    except Exception as exc:  # report unexpected WS errors (Requirement 19.5)
        sentry_sdk.capture_exception(exc)
        logger.exception("ws error on thread %s: %s", thread_id, exc)
    finally:
        await manager.disconnect(thread_id, websocket)


async def _handle_frame(frame: dict, thread_id: str, user_id: str, peer_origin, websocket) -> None:
    ftype = frame.get("type")

    if ftype == "message":
        body = (frame.get("body") or "").strip()
        if not body:
            return
        async with acquire(user_id) as conn:
            row = await threads_repo.insert_message(conn, thread_id, user_id, body)
        msg = Message(
            id=str(row["id"]),
            thread_id=str(row["thread_id"]),
            sender_id=str(row["sender_id"]),
            body=row["body"],
            read_at=row["read_at"],
            expires_at=row["expires_at"],
            created_at=row["created_at"],
        )
        frame_out = {"type": "message", **json.loads(msg.model_dump_json())}
        await manager.publish(thread_id, frame_out)

    elif ftype == "read":
        up_to = frame.get("up_to_message_id")
        if not up_to:
            return
        async with acquire(user_id) as conn:
            updated = await threads_repo.mark_read(conn, thread_id, user_id, up_to)
        for r in updated:
            await manager.publish(
                thread_id,
                {
                    "type": "read_receipt",
                    "message_id": str(r["id"]),
                    "read_at": r["read_at"].isoformat(),
                },
            )

    elif ftype == "heartbeat":
        # Dual-expiry: if the sender has left the peer's discovery radius, expire now.
        lat, lng = frame.get("lat"), frame.get("lng")
        if lat is None or lng is None or peer_origin is None or peer_origin["lat"] is None:
            return
        out_of_range = is_out_of_range(
            lat, lng, peer_origin["lat"], peer_origin["lng"], peer_origin["radius_m"]
        )
        if out_of_range:
            async with acquire(user_id) as conn:
                await threads_repo.expire_thread(conn, thread_id)
            await manager.publish(
                thread_id, {"type": "thread_expired", "reason": "range_exit"}
            )
