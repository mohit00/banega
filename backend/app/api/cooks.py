"""Cooks and duty (contract §Cooks and duty)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Query, status
from sqlalchemy import select

from app.api.deps import DB, HouseholdCtx
from app.core.errors import AppError, Forbidden
from app.models import User
from app.permissions import Action, Resource, can
from app.schemas import normalise_phone
from app.schemas_kitchen import CookIn, CookOut, CookPatch, DutyEntryOut
from app.services import cooks as cook_svc

router = APIRouter(prefix="/cooks", tags=["cooks"])


async def _cook_out(db: DB, cook_id: uuid.UUID, ctx: HouseholdCtx) -> CookOut:
    cook = await cook_svc.get_cook(db, ctx.household, cook_id)
    phone = None
    if cook.user_id is not None and not cook.phone:
        phone = (await db.execute(select(User.phone).where(User.id == cook.user_id))).scalar()
    return CookOut.model_validate(cook_svc.cook_view(cook, phone))


@router.get("", response_model=list[CookOut])
async def list_cooks(ctx: HouseholdCtx, db: DB) -> list[CookOut]:
    return [CookOut.model_validate(c) for c in await cook_svc.list_cooks(db, ctx.household)]


@router.post("", response_model=CookOut, status_code=status.HTTP_201_CREATED)
async def create_cook(body: CookIn, ctx: HouseholdCtx, db: DB) -> CookOut:
    data = body.model_dump()
    if data.get("phone"):
        try:
            data["phone"] = normalise_phone(data["phone"])
        except ValueError as exc:
            raise AppError(
                "invalid_phone",
                "Enter a valid mobile number.",
                "Sahi mobile number daaliye.",
                status_code=422,
            ) from exc
    cook = await cook_svc.create_cook(db, ctx.household, ctx.actor, data)
    await db.commit()
    return await _cook_out(db, cook.id, ctx)


@router.patch("/{cook_id}", response_model=CookOut)
async def patch_cook(cook_id: uuid.UUID, body: CookPatch, ctx: HouseholdCtx, db: DB) -> CookOut:
    cook = await cook_svc.get_cook(db, ctx.household, cook_id)
    await cook_svc.patch_cook(
        db, ctx.household, cook, ctx.actor, body.model_dump(exclude_unset=True)
    )
    await db.commit()
    return await _cook_out(db, cook.id, ctx)


@router.delete("/{cook_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_cook(cook_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> None:
    cook = await cook_svc.get_cook(db, ctx.household, cook_id)
    await cook_svc.remove_cook(db, ctx.household, cook, ctx.actor)
    await db.commit()


@router.get("/{cook_id}/duty-history", response_model=list[DutyEntryOut])
async def duty_history(
    cook_id: uuid.UUID,
    ctx: HouseholdCtx,
    db: DB,
    month: Annotated[str | None, Query(pattern=r"^\d{4}-\d{2}$")] = None,
) -> list[DutyEntryOut]:
    """FR-K13 (Should): On/Off changes in one month (household time). Admin or the cook."""
    cook = await cook_svc.get_cook(db, ctx.household, cook_id)
    if not can(ctx.actor, Action.set_duty, Resource(owner_user_id=cook.user_id)):
        raise Forbidden(details={"action": Action.set_duty.value})
    tz = ZoneInfo(ctx.household.timezone or "Asia/Kolkata")
    try:
        first = (
            date.fromisoformat(f"{month}-01") if month else datetime.now(tz).date().replace(day=1)
        )
    except ValueError as exc:
        raise AppError(
            "invalid_month", "Use YYYY-MM.", "Mahina YYYY-MM mein.", status_code=422
        ) from exc
    nxt = date(first.year + (first.month == 12), first.month % 12 + 1, 1)
    start = datetime.combine(first, datetime.min.time(), tzinfo=tz)
    end = datetime.combine(nxt, datetime.min.time(), tzinfo=tz)
    rows = await cook_svc.duty_history(db, cook, start, end)
    return [
        DutyEntryOut(at=r.at, on_duty=r.on_duty, until=r.until, reason=r.reason, by=r.by_user_id)
        for r in rows
    ]
