"""FastAPI application entry point: ``uvicorn app.main:app``."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI
from sqlalchemy import text

from app.api import (
    approvals,
    auth,
    billing,
    catalogue,
    chat,
    cooks,
    devices,
    feedback,
    households,
    inbox,
    invites,
    me,
    members,
    menus,
    recommendations,
    stock,
    tickets,
)
from app.core.config import get_settings
from app.core.db import dispose_engine, get_engine
from app.core.errors import install_error_handlers
from app.core.kv import get_kv
from app.core.logging_setup import configure_logging
from app.core.middleware import IdempotencyMiddleware, RequestIdMiddleware

API_PREFIX = "/v1"


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    yield
    await dispose_engine()


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.LOG_LEVEL, settings.LOG_JSON)
    app = FastAPI(
        title="Banega API",
        version="0.1.0",
        # The schema is for the app build and dev tools, not the public (review, low).
        openapi_url=None if settings.ENV == "prod" else f"{API_PREFIX}/openapi.json",
        docs_url=f"{API_PREFIX}/docs" if settings.is_dev else None,
        redoc_url=None,
        lifespan=lifespan,
    )
    install_error_handlers(app)
    # Order: RequestId is outermost so every log line (incl. idempotency replays) has an id.
    app.add_middleware(IdempotencyMiddleware)
    app.add_middleware(RequestIdMiddleware)

    v1 = APIRouter(prefix=API_PREFIX)

    @v1.get("/health", tags=["meta"])
    async def health() -> dict[str, str]:
        return {"status": "ok", "env": settings.ENV}

    @v1.get("/health/ready", tags=["meta"])
    async def ready() -> dict[str, str]:
        """Readiness: database and Redis reachable."""
        async with get_engine().connect() as conn:
            await conn.execute(text("SELECT 1"))
        await get_kv().get("health:ping")
        return {"status": "ready"}

    for module in (
        auth,
        households,
        members,
        invites,
        me,
        devices,
        catalogue,
        recommendations,
        chat,
        menus,
        tickets,
        cooks,
        inbox,
        stock,
        approvals,
        feedback,
        billing,
    ):
        v1.include_router(module.router)
    app.include_router(v1)
    return app


app = create_app()
