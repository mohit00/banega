"""``{id, name}`` references for users named in Phase 6-7 responses (updated_by, raised_by,
requested_by, decided_by)."""

from __future__ import annotations

import uuid
from collections.abc import Iterable
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Cook, HouseholdMembership, Member, User


async def user_names(db: AsyncSession, ids: Iterable[uuid.UUID | None]) -> dict[uuid.UUID, str]:
    wanted = {i for i in ids if i is not None}
    if not wanted:
        return {}
    rows = await db.execute(select(User.id, User.name).where(User.id.in_(wanted)))
    names = {r[0]: (r[1] or "").strip() for r in rows.all()}
    # Cooks and invited members often never set User.name: use their cook name or the
    # family profile their membership links to.
    missing = {i for i in wanted if not names.get(i)}
    if missing:
        cooks = await db.execute(
            select(Cook.user_id, Cook.name).where(Cook.user_id.in_(missing), Cook.name != "")
        )
        for uid, name in cooks.all():
            if uid is not None and name:
                names[uid] = name
        missing = {i for i in wanted if not names.get(i)}
    if missing:
        members = await db.execute(
            select(HouseholdMembership.user_id, Member.name)
            .join(Member, Member.id == HouseholdMembership.member_id)
            .where(HouseholdMembership.user_id.in_(missing))
        )
        for uid, name in members.all():
            if name:
                names[uid] = name
    return {i: names.get(i, "") for i in wanted}


def ref(user_id: uuid.UUID | None, names: dict[uuid.UUID, str]) -> dict[str, Any] | None:
    if user_id is None:
        return None
    return {"id": user_id, "name": names.get(user_id, "")}
