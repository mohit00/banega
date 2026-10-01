"""In-app inbox (contract §Notifications): the source of truth; push is best effort."""

from __future__ import annotations

import base64
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query, Response
from sqlalchemy import and_, or_, select

from app.api.deps import DB, HouseholdCtx
from app.core.errors import AppError, NotFound
from app.core.security import utcnow
from app.models import InboxItem
from app.schemas_kitchen import InboxItemOut

router = APIRouter(prefix="/inbox", tags=["inbox"])

NEXT_CURSOR_HEADER = "X-Next-Cursor"


def _encode(item: InboxItem) -> str:
    return base64.urlsafe_b64encode(f"{item.created_at.isoformat()}|{item.id}".encode()).decode()


def _decode(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        ts, iid = base64.urlsafe_b64decode(cursor.encode()).decode().split("|", 1)
        return datetime.fromisoformat(ts), uuid.UUID(iid)
    except (ValueError, UnicodeDecodeError) as exc:
        raise AppError("invalid_cursor", "Invalid cursor.", "Cursor galat hai.") from exc


@router.get("", response_model=list[InboxItemOut])
async def list_inbox(
    ctx: HouseholdCtx,
    db: DB,
    response: Response,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    unread: bool = False,
) -> list[InboxItemOut]:
    """Newest first. The next page's cursor is in the ``X-Next-Cursor`` header."""
    stmt = select(InboxItem).where(
        InboxItem.user_id == ctx.user.id, InboxItem.household_id == ctx.household.id
    )
    if unread:
        stmt = stmt.where(InboxItem.read_at.is_(None))
    if cursor:
        ts, iid = _decode(cursor)
        stmt = stmt.where(
            or_(InboxItem.created_at < ts, and_(InboxItem.created_at == ts, InboxItem.id < iid))
        )
    rows = list(
        (
            await db.execute(
                stmt.order_by(InboxItem.created_at.desc(), InboxItem.id.desc()).limit(limit + 1)
            )
        ).scalars()
    )
    if len(rows) > limit:
        response.headers[NEXT_CURSOR_HEADER] = _encode(rows[limit - 1])
    return [InboxItemOut.model_validate(r, from_attributes=True) for r in rows[:limit]]


@router.post("/{item_id}/read", response_model=InboxItemOut)
async def mark_read(item_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> InboxItemOut:
    item = await db.get(InboxItem, item_id)
    if item is None or item.user_id != ctx.user.id:
        raise NotFound()
    if item.read_at is None:
        item.read_at = utcnow()
        await db.commit()
    return InboxItemOut.model_validate(item, from_attributes=True)
