"""Shared fixtures.

The suite runs on SQLite in memory by default. Set ``TEST_DATABASE_URL`` to a Postgres
database (``postgresql+asyncpg://...``; the pgvector extension must be installable) to run the
same tests against Postgres: the schema is created once per session from the models and every
test starts from empty tables (TRUNCATE). ``scripts/test-postgres.sh`` does both, plus the
Alembic upgrade / downgrade round trip.
"""

from __future__ import annotations

import os
import tempfile

TEST_DATABASE_URL = (
    os.environ.get("TEST_DATABASE_URL", "").strip() or "sqlite+aiosqlite:///:memory:"
)
IS_POSTGRES = TEST_DATABASE_URL.startswith("postgresql")

os.environ.update(
    {
        "ENV": "test",
        "DATABASE_URL": TEST_DATABASE_URL,
        "REDIS_URL": "memory://",
        "JWT_SECRET": "test-secret-at-least-32-bytes-long!!",
        "OTP_PROVIDER": "dev",
        "OTP_RESEND_SECONDS": "0",
        # Every test client is 127.0.0.1; the per-IP limit has its own test.
        "OTP_MAX_PER_IP_PER_HOUR": "10000",
        # Recipes change inside a test (seed, publish): re-check the snapshot stamp each call.
        "CATALOGUE_CACHE_SECONDS": "0",
        "LOG_JSON": "false",
        "LOG_LEVEL": "WARNING",
        # Data exports land here, never in the repo.
        "MEDIA_DIR": tempfile.mkdtemp(prefix="banega-media-"),
    }
)

from collections.abc import AsyncIterator, Awaitable, Callable

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.core.config import get_settings
from app.core.db import dispose_engine, make_engine, set_engine
from app.core.kv import MemoryStore, set_kv
from app.main import app
from app.models import Base
from app.services import catalogue_cache

get_settings.cache_clear()

Headers = dict[str, str]
Login = Callable[..., Awaitable[Headers]]

_pg_schema_ready = False


async def _prepare_postgres() -> None:
    """Once per session: a fresh schema from the models (drop + create)."""
    global _pg_schema_ready
    engine = make_engine(TEST_DATABASE_URL)
    async with engine.begin() as conn:
        await conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        await conn.execute(text("DROP TABLE IF EXISTS alembic_version"))
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()
    _pg_schema_ready = True


async def _empty_postgres() -> None:
    # DELETE (children first) is much faster than TRUNCATE on small tables: TRUNCATE swaps
    # and fsyncs a new file per table.
    engine = make_engine(TEST_DATABASE_URL)
    async with engine.begin() as conn:
        for table in reversed(Base.metadata.sorted_tables):
            await conn.execute(table.delete())
    await engine.dispose()


@pytest.fixture(autouse=True)
async def _db() -> AsyncIterator[None]:
    if IS_POSTGRES:
        if not _pg_schema_ready:
            await _prepare_postgres()
        else:
            await _empty_postgres()
        engine = make_engine(TEST_DATABASE_URL)
    else:
        engine = make_engine("sqlite+aiosqlite:///:memory:")
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    set_engine(engine)
    set_kv(MemoryStore())
    catalogue_cache.reset()
    yield
    await dispose_engine()
    set_kv(None)


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture
def login(client: AsyncClient) -> Login:
    async def _login(phone: str = "+919800000001", device_id: str | None = None) -> Headers:
        r = await client.post("/v1/auth/otp", json={"phone": phone, "device_id": device_id})
        assert r.status_code == 200, r.text
        code = r.json()["dev_code"]
        r = await client.post("/v1/auth/verify", json={"phone": phone, "code": code})
        assert r.status_code == 200, r.text
        return {"Authorization": f"Bearer {r.json()['access_token']}"}

    return _login


@pytest.fixture
def make_household(client: AsyncClient, login: Login) -> Callable[..., Awaitable[Headers]]:
    async def _make(phone: str = "+919800000001", name: str = "Sharma ghar") -> Headers:
        headers = await login(phone)
        r = await client.post("/v1/households", json={"name": name}, headers=headers)
        assert r.status_code == 201, r.text
        return headers

    return _make
