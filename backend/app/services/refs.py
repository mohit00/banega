"""``{id, name}`` references for users named in Phase 6-7 responses (updated_by, raised_by,
requested_by, decided_by)."""

from __future__ import annotations

import uuid
from collections.abc import Iterable
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User


async def user_names(db: AsyncSession, ids: Iterable[uuid.UUID | None]) -> dict[uuid.UUID, str]:
    wanted = {i for i in ids if i is not None}
    if not wanted:
        return {}
    rows = await db.execute(select(User.id, User.name).where(User.id.in_(wanted)))
    return {r[0]: r[1] or "" for r in rows.all()}


def ref(user_id: uuid.UUID | None, names: dict[uuid.UUID, str]) -> dict[str, Any] | None:
    if user_id is None:
        return None
    return {"id": user_id, "name": names.get(user_id, "")}
