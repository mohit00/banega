"""Once-per-household-per-local-day markers (review H1): replaces "is there already an inbox
item since X?" scans with one unique row in ``notification_marks``."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import NotificationMark


async def is_marked(db: AsyncSession, household_id: uuid.UUID, kind: str, day: date) -> bool:
    row = await db.execute(
        select(NotificationMark.id).where(
            NotificationMark.household_id == household_id,
            NotificationMark.kind == kind,
            NotificationMark.local_date == day,
        )
    )
    return row.first() is not None


async def claim(db: AsyncSession, household_id: uuid.UUID, kind: str, day: date) -> bool:
    """True if this call created the mark (the caller sends); False if it already existed,
    including when a concurrent worker won the race (unique constraint)."""
    if await is_marked(db, household_id, kind, day):
        return False
    try:
        async with db.begin_nested():
            db.add(NotificationMark(household_id=household_id, kind=kind, local_date=day))
            await db.flush()
    except IntegrityError:
        return False
    return True
