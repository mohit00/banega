"""Member (food profile) CRUD, scoped to the caller's household. Delete archives."""

from __future__ import annotations

import base64
import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query, status
from sqlalchemy import and_, or_, select

from app.api.deps import DB, HouseholdCtx
from app.core.errors import AppError, Forbidden, NotFound
from app.core.security import utcnow
from app.models import Member
from app.permissions import Action, Resource, can
from app.schemas import MemberIn, MemberOut, MemberPatch, Page

router = APIRouter(prefix="/members", tags=["members"])


def _encode_cursor(m: Member) -> str:
    return base64.urlsafe_b64encode(f"{m.created_at.isoformat()}|{m.id}".encode()).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        ts, mid = base64.urlsafe_b64decode(cursor.encode()).decode().split("|", 1)
        return datetime.fromisoformat(ts), uuid.UUID(mid)
    except (ValueError, UnicodeDecodeError) as exc:
        raise AppError("invalid_cursor", "Invalid cursor.", "Cursor galat hai.") from exc


async def _get_member(db: DB, ctx: HouseholdCtx, member_id: uuid.UUID) -> Member:
    member = await db.get(Member, member_id)
    # Foreign or unknown ids are indistinguishable: always 404.
    if member is None or member.household_id != ctx.household.id:
        raise NotFound()
    return member


@router.get("", response_model=Page[MemberOut])
async def list_members(
    ctx: HouseholdCtx,
    db: DB,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    include_archived: bool = False,
) -> Page[MemberOut]:
    stmt = select(Member).where(Member.household_id == ctx.household.id)
    if not include_archived:
        stmt = stmt.where(Member.archived_at.is_(None))
    if cursor:
        ts, mid = _decode_cursor(cursor)
        stmt = stmt.where(
            or_(Member.created_at > ts, and_(Member.created_at == ts, Member.id > mid))
        )
    rows = list(
        (await db.execute(stmt.order_by(Member.created_at, Member.id).limit(limit + 1))).scalars()
    )
    next_cursor = _encode_cursor(rows[limit - 1]) if len(rows) > limit else None
    return Page[MemberOut](
        items=[MemberOut.model_validate(m) for m in rows[:limit]], next_cursor=next_cursor
    )


@router.post("", response_model=MemberOut, status_code=status.HTTP_201_CREATED)
async def create_member(body: MemberIn, ctx: HouseholdCtx, db: DB) -> MemberOut:
    ctx.require(Action.manage_members)
    member = Member(
        household_id=ctx.household.id,
        **{k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None},
    )
    db.add(member)
    await db.commit()
    await db.refresh(member)
    return MemberOut.model_validate(member)


@router.get("/{member_id}", response_model=MemberOut)
async def get_member(member_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> MemberOut:
    return MemberOut.model_validate(await _get_member(db, ctx, member_id))


@router.patch("/{member_id}", response_model=MemberOut)
async def update_member(
    member_id: uuid.UUID, body: MemberPatch, ctx: HouseholdCtx, db: DB
) -> MemberOut:
    member = await _get_member(db, ctx, member_id)
    own = Resource(owner_member_id=member.id)
    if not (can(ctx.actor, Action.manage_members) or can(ctx.actor, Action.edit_own_profile, own)):
        raise Forbidden(details={"action": Action.edit_own_profile.value})
    for field, value in body.model_dump(exclude_unset=True).items():
        if field == "allergens_other":
            member.allergens_other = (value or "").strip() or None  # null / "" clears it
        elif value is not None:
            setattr(member, field, value)
    await db.commit()
    await db.refresh(member)
    return MemberOut.model_validate(member)


@router.delete("/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
async def archive_member(member_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> None:
    ctx.require(Action.manage_members)
    member = await _get_member(db, ctx, member_id)
    if member.archived_at is None:
        member.archived_at = utcnow()
        await db.commit()
