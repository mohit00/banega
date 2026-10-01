"""Pantry stock and ration requests (contract Phase 6)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.deps import DB, HouseholdCtx
from app.core.errors import AppError
from app.models import RationStatus
from app.permissions import Action
from app.schemas_pantry import (
    DecisionIn,
    RationRequestIn,
    RationRequestOut,
    RationSuggestionOut,
    StockBulkIn,
    StockItemOut,
    StockPut,
)
from app.services import ration as ration_svc
from app.services import stock as stock_svc

router = APIRouter(tags=["stock"])


@router.get("/stock", response_model=list[StockItemOut])
async def list_stock(ctx: HouseholdCtx, db: DB) -> list[StockItemOut]:
    """Every tracked staple (defaults to ``in`` on first read), in catalogue order."""
    items = await stock_svc.list_stock(db, ctx.household)
    await db.commit()
    return [StockItemOut.model_validate(i) for i in items]


@router.put("/stock/{ingredient_id}", response_model=StockItemOut)
async def put_stock(
    ingredient_id: uuid.UUID, body: StockPut, ctx: HouseholdCtx, db: DB
) -> StockItemOut:
    ctx.require(Action.update_stock)
    item = {"ingredient_id": ingredient_id, **body.model_dump(exclude_unset=True)}
    await stock_svc.update_levels(db, ctx.household, [item], by=ctx.user.id)
    await db.commit()
    return StockItemOut.model_validate(await stock_svc.stock_item(db, ctx.household, ingredient_id))


@router.post("/stock/bulk", response_model=list[StockItemOut])
async def bulk_stock(body: StockBulkIn, ctx: HouseholdCtx, db: DB) -> list[StockItemOut]:
    ctx.require(Action.update_stock)
    items = [i.model_dump() for i in body.items]
    await stock_svc.update_levels(db, ctx.household, items, by=ctx.user.id)
    await db.commit()
    return [
        StockItemOut.model_validate(await stock_svc.stock_item(db, ctx.household, i.ingredient_id))
        for i in body.items
    ]


# ---- ration ---------------------------------------------------------------------------------


@router.post(
    "/ration-requests", response_model=RationRequestOut, status_code=status.HTTP_201_CREATED
)
async def raise_ration(body: RationRequestIn, ctx: HouseholdCtx, db: DB) -> RationRequestOut:
    req = await ration_svc.raise_request(
        db,
        ctx.household,
        ctx.actor,
        items=[i.model_dump() for i in body.items],
        ticket_id=body.ticket_id,
        note=body.note,
    )
    await db.commit()
    await db.refresh(req)
    return RationRequestOut.model_validate(await ration_svc.request_out(db, req))


@router.get("/ration-requests", response_model=list[RationRequestOut])
async def list_ration(
    ctx: HouseholdCtx,
    db: DB,
    status_: Annotated[str | None, Query(alias="status")] = None,
) -> list[RationRequestOut]:
    """Newest first. A cook-only login sees her own requests."""
    wanted: list[RationStatus] = []
    if status_:
        try:
            wanted = [RationStatus(s.strip()) for s in status_.split(",") if s.strip()]
        except ValueError as exc:
            raise AppError(
                "invalid_status", "Unknown status.", "Ye status nahi hai.", status_code=422
            ) from exc
    rows = await ration_svc.list_requests(
        db,
        ctx.household,
        status=wanted,
        raised_by=ctx.user.id if ctx.cook_only else None,
    )
    return [RationRequestOut.model_validate(await ration_svc.request_out(db, r)) for r in rows]


@router.get("/ration-requests/suggest", response_model=list[RationSuggestionOut])
async def suggest_ration(
    ctx: HouseholdCtx, db: DB, days: Annotated[int, Query(ge=1, le=14)] = 7
) -> list[RationSuggestionOut]:
    rows = await ration_svc.suggest(db, ctx.household, days)
    return [RationSuggestionOut.model_validate(r) for r in rows]


@router.post("/ration-requests/{request_id}/decide", response_model=RationRequestOut)
async def decide_ration(
    request_id: uuid.UUID, body: DecisionIn, ctx: HouseholdCtx, db: DB
) -> RationRequestOut:
    req = await ration_svc.get_request(db, ctx.household, request_id)
    await ration_svc.decide(db, ctx.household, req, ctx.actor, body.decision, note=body.note)
    await db.commit()
    await db.refresh(req)
    return RationRequestOut.model_validate(await ration_svc.request_out(db, req))


@router.post("/ration-requests/{request_id}/bought", response_model=RationRequestOut)
async def bought_ration(request_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> RationRequestOut:
    req = await ration_svc.get_request(db, ctx.household, request_id)
    await ration_svc.mark_bought(db, ctx.household, req, ctx.actor)
    await db.commit()
    await db.refresh(req)
    return RationRequestOut.model_validate(await ration_svc.request_out(db, req))
