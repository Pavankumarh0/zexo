"""Zexo API application factory.

Initialises Sentry, the asyncpg pool, and Redis, registers routers, and installs a
consistent error envelope. Run with: `uvicorn app.main:app`.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

import sentry_sdk
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sentry_sdk.integrations.fastapi import FastApiIntegration

from app.core.config import get_settings
from app.core.db import close_pool, init_pool
from app.core.redis import close_redis, init_redis
from app.routers import auth, discover, events, threads, users

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("zexo")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    if settings.sentry_dsn:
        sentry_sdk.init(
            dsn=settings.sentry_dsn,
            environment=settings.zexo_env,
            integrations=[FastApiIntegration()],
            traces_sample_rate=0.1,
        )
    await init_pool()
    if settings.redis_url:
        await init_redis()
    logger.info("Zexo API started (env=%s)", settings.zexo_env)
    try:
        yield
    finally:
        await close_pool()
        await close_redis()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Zexo API",
        version="0.1.0",
        description="Proximity-first social discovery backend.",
        debug=settings.zexo_debug,
        lifespan=lifespan,
    )

    @app.exception_handler(RequestValidationError)
    async def _validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "validation_error", "message": str(exc.errors())}},
        )

    @app.get("/health", tags=["meta"])
    async def health() -> dict:
        return {"status": "ok", "service": "zexo-api", "version": "0.1.0"}

    app.include_router(auth.router)
    app.include_router(users.router)
    app.include_router(discover.router)
    app.include_router(threads.router)
    app.include_router(events.router)
    return app


app = create_app()
