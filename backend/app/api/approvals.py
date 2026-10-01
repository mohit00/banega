"""Approvals (§2.1): swaps, dish changes and ration requests waiting for an answer."""

from __future__ import annotations

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Query

from app.api.deps import DB, HouseholdCtx
from app.core.errors import Forbidden
from app.schemas_pantry import ApprovalDecideIn, ApprovalOut
from app.services import ladder
from app.services.refs import user_names

router = APIRouter(prefix="/approvals", tags=["approvals"])


@router.get("", response_model=list[ApprovalOut])
async def list_approvals(
    ctx: HouseholdCtx,
    db: DB,
    status: Annotated[Literal["pending", "approved", "rejected", "expired"] | None, Query()] = None,
) -> list[ApprovalOut]:
    """Admins and adult members see the household's approvals; a cook sees her own."""
    family = ctx.actor.is_admin or ctx.actor.is_member
    rows = await ladder.list_approvals(
        db, ctx.household, status=status, requested_by=None if family else ctx.user.id
    )
    names = await user_names(db, [u for a in rows for u in (a.requested_by, a.decided_by)])
    return [ApprovalOut.model_validate(ladder.approval_view(a, names=names)) for a in rows]


@router.post("/{approval_id}/decide", response_model=ApprovalOut)
async def decide(
    approval_id: uuid.UUID, body: ApprovalDecideIn, ctx: HouseholdCtx, db: DB
) -> ApprovalOut:
    """First response wins: a second answer is 409 ``already_decided``."""
    if ctx.cook_only:
        raise Forbidden(details={"reason": "cook_mode"})
    approval = await ladder.get_approval(db, ctx.household, approval_id)
    await ladder.decide(db, ctx.household, approval, ctx.actor, body.decision)
    await db.commit()
    await db.refresh(approval)
    names = await user_names(db, [approval.requested_by, approval.decided_by])
    return ApprovalOut.model_validate(ladder.approval_view(approval, names=names))
