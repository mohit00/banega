"""Ration requests (FRD FR-S5..S8 as amended by F-5.8-04, F-2-02/04).

- Raise (``raise_ration``: admin, hired cook, family cook). A cook's free-text item is matched
  to the catalogue by alias ("pyaaz" -> Onion); no match keeps the text (``ingredient_id``
  null). An admin or family cook raising her own list is auto-approved (F-2-04): the
  ``Approval`` row is written with ``auto=true`` for the log.
- Decide (``approve_ration``: admin; family cook for her own request). First response wins.
- Bought (``mark_bought``): tracked items go back to ``in``; the raiser is told.
- Suggest (Should): items needed by open tickets in the next N days that are low/out, then
  any other low/out tracked item (FR-S5 pre-fill).
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping, Sequence
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.models import (
    Approval,
    ApprovalDecision,
    ApprovalType,
    Household,
    Ingredient,
    RationItem,
    RationRequest,
    RationStatus,
    StockLevel,
    Ticket,
)
from app.models.base import utcnow
from app.permissions import Action, Actor, Resource, can, resolve_approval
from app.services import menus as menu_svc
from app.services import notifications as notify
from app.services import stock as stock_svc
from app.services import tickets as ticket_svc
from app.services.refs import ref, user_names

R = RationStatus


# ---- free-text resolution ---------------------------------------------------------------------


async def resolve_name(db: AsyncSession, text: str) -> Ingredient | None:
    """Catalogue ingredient for a cook's free text, by alias (longest match first)."""
    from app.services.importer import build_matcher

    matcher, by_slug = await build_matcher(db)
    slugs = matcher.match(text)
    return by_slug[slugs[0]] if slugs else None


async def _items(db: AsyncSession, raw: Sequence[Mapping[str, Any]]) -> list[RationItem]:
    if not raw:
        raise Conflict("ration_empty", "Add at least one item.", "Kam se kam ek saaman jodiye.")
    out: list[RationItem] = []
    for order, it in enumerate(raw):
        ing: Ingredient | None = None
        name = (it.get("name") or "").strip()
        if it.get("ingredient_id") is not None:
            ing = await db.get(Ingredient, it["ingredient_id"])
            if ing is None:
                raise NotFound(
                    "ingredient_not_found", details={"ingredient_id": str(it["ingredient_id"])}
                )
        elif name:
            ing = await resolve_name(db, name)
        else:
            raise AppError(
                "item_name_required",
                "Each item needs an ingredient or a name.",
                "Har saaman ka naam dijiye.",
                status_code=422,
            )
        qty = it.get("qty")
        out.append(
            RationItem(
                ingredient_id=ing.id if ing is not None else None,
                name=(name or (ing.name_en if ing is not None else ""))[:120],
                qty=Decimal(str(qty)) if qty is not None else None,
                unit=it.get("unit") or (ing.purchase_unit if ing is not None else None),
                note=it.get("note"),
                sort_order=order,
            )
        )
    return out


# ---- views ------------------------------------------------------------------------------------


def request_view(
    req: RationRequest, names: Mapping[uuid.UUID, str] | None = None
) -> dict[str, Any]:
    names = dict(names or {})
    return {
        "id": req.id,
        "ticket_id": req.ticket_id,
        "items": [
            {
                "ingredient_id": i.ingredient_id,
                "name": i.name,
                "qty": float(i.qty) if i.qty is not None else None,
                "unit": i.unit,
                "note": i.note,
            }
            for i in req.items
        ],
        "status": str(req.status),
        "raised_by": ref(req.raised_by, names),
        "auto_approved": req.auto_approved,
        "decided_by": ref(req.decided_by, names),
        "decided_at": req.decided_at,
        "note": req.note,
        "decision_note": req.decision_note,
        "bought_at": req.bought_at,
        "created_at": req.created_at,
    }


def _items_line(req: RationRequest) -> str:
    return ", ".join(i.name for i in req.items)[:180]


async def request_out(db: AsyncSession, req: RationRequest) -> dict[str, Any]:
    names = await user_names(db, [req.raised_by, req.decided_by])
    return request_view(req, names)


async def get_request(
    db: AsyncSession, household: Household, request_id: uuid.UUID
) -> RationRequest:
    req = await db.get(RationRequest, request_id)
    if req is None or req.household_id != household.id:
        raise NotFound()
    return req


async def list_requests(
    db: AsyncSession,
    household: Household,
    *,
    status: Sequence[RationStatus] | None = None,
    raised_by: uuid.UUID | None = None,
) -> list[RationRequest]:
    stmt = select(RationRequest).where(RationRequest.household_id == household.id)
    if status:
        stmt = stmt.where(RationRequest.status.in_(list(status)))
    if raised_by is not None:
        stmt = stmt.where(RationRequest.raised_by == raised_by)
    return list((await db.execute(stmt.order_by(RationRequest.created_at.desc()))).scalars())


# ---- raise / decide / bought ------------------------------------------------------------------


async def raise_request(
    db: AsyncSession,
    household: Household,
    actor: Actor,
    *,
    items: Sequence[Mapping[str, Any]],
    ticket_id: uuid.UUID | None = None,
    note: str | None = None,
    now: datetime | None = None,
) -> RationRequest:
    now = now or utcnow()
    if not can(actor, Action.raise_ration):
        raise Forbidden(details={"action": Action.raise_ration.value})
    ticket: Ticket | None = None
    if ticket_id is not None:
        ticket = await ticket_svc.get_ticket(db, household, ticket_id)
    outcome = resolve_approval(
        actor, Action.approve_ration, Resource(requested_by_user_id=actor.user_id)
    )
    req = RationRequest(
        household_id=household.id,
        ticket_id=ticket.id if ticket else None,
        status=R.approved if outcome.self_approved else R.pending,
        raised_by=actor.user_id,
        auto_approved=outcome.self_approved,
        decided_by=actor.user_id if outcome.self_approved else None,
        decided_at=now if outcome.self_approved else None,
        # The app reads "self_approved" from the note when the raiser left none.
        note=note or ("self_approved" if outcome.self_approved else None),
        decision_note="self_approved" if outcome.self_approved else None,
        items=await _items(db, items),
    )
    db.add(req)
    await db.flush()
    db.add(
        Approval(
            household_id=household.id,
            ticket_id=ticket.id if ticket else None,
            ration_request_id=req.id,
            type=ApprovalType.ration,
            requested_by=actor.user_id,
            decided_by=actor.user_id if outcome.self_approved else None,
            decision=ApprovalDecision.approved if outcome.self_approved else None,
            decided_at=now if outcome.self_approved else None,
            auto=outcome.self_approved,
            payload={"ration_request_id": str(req.id), "items": [i.name for i in req.items]},
            created_at=now,
        )
    )
    if ticket is not None:
        ticket_svc.log_event(
            db,
            ticket,
            "ration_requested",
            actor.user_id,
            {
                "ration_request_id": str(req.id),
                "items": [i.name for i in req.items],
                "self_approved": outcome.self_approved,
            },
            now,
        )
    await notify.emit(
        db,
        "ration_request",
        household,
        actor_user_id=actor.user_id,
        params={"cook": await _name(db, actor.user_id), "items": _items_line(req)},
        data={"ration_request_id": req.id},
        now=now,
    )
    await db.flush()
    return req


async def _name(db: AsyncSession, user_id: uuid.UUID | None) -> str:
    from app.models import User

    user = await db.get(User, user_id) if user_id else None
    return (user.name if user and user.name else None) or "Cook"


async def _approval_for(db: AsyncSession, req: RationRequest) -> Approval | None:
    return (
        await db.execute(
            select(Approval).where(
                Approval.ration_request_id == req.id, Approval.type == ApprovalType.ration
            )
        )
    ).scalar_one_or_none()


def _already_decided(req: RationRequest) -> Conflict:
    return Conflict(
        "already_decided",
        "Somebody already answered this request.",
        "Is request ka jawab pehle hi de diya gaya hai.",
        details={"status": str(req.status)},
    )


async def decide(
    db: AsyncSession,
    household: Household,
    req: RationRequest,
    actor: Actor,
    decision: str,
    *,
    note: str | None = None,
    now: datetime | None = None,
) -> RationRequest:
    now = now or utcnow()
    res = Resource(requested_by_user_id=req.raised_by)
    if not resolve_approval(actor, Action.approve_ration, res).allowed:
        raise Forbidden(details={"action": Action.approve_ration.value})
    target = R.approved if decision == "approved" else R.rejected
    # First response wins: a guarded UPDATE on the pending row.
    result = await db.execute(
        update(RationRequest)
        .where(RationRequest.id == req.id, RationRequest.status == R.pending)
        .values(status=target, decided_by=actor.user_id, decided_at=now, decision_note=note)
        .execution_options(synchronize_session=False)
    )
    if result.rowcount != 1:  # type: ignore[attr-defined]
        await db.refresh(req)
        raise _already_decided(req)
    await db.refresh(req)
    approval = await _approval_for(db, req)
    if approval is not None and approval.decision is None:
        approval.decision = ApprovalDecision(str(target))
        approval.decided_by = actor.user_id
        approval.decided_at = now
    await notify.emit(
        db,
        "ration_decided",
        household,
        actor_user_id=actor.user_id,
        requester=req.raised_by,
        params={
            "decision": "manzoor" if target == R.approved else "mana",
            "items": _items_line(req),
            "note": note or "",
        },
        data={"ration_request_id": req.id},
        now=now,
    )
    return req


async def mark_bought(
    db: AsyncSession,
    household: Household,
    req: RationRequest,
    actor: Actor,
    *,
    now: datetime | None = None,
) -> RationRequest:
    now = now or utcnow()
    res = Resource(requested_by_user_id=req.raised_by)
    if not can(actor, Action.mark_bought, res):
        raise Forbidden(details={"action": Action.mark_bought.value})
    if req.status != R.approved:
        raise Conflict(
            "not_approved",
            "Only an approved request can be marked bought.",
            "Sirf manzoor request ko khareeda hua mark kar sakte hain.",
            details={"status": str(req.status)},
        )
    tracked = await stock_svc.staple_ids(db)
    for item in req.items:
        if item.ingredient_id is not None and item.ingredient_id in tracked:
            await stock_svc.set_level(
                db, household, item.ingredient_id, StockLevel.in_, by=actor.user_id, now=now
            )
    req.status = R.bought
    req.bought_by = actor.user_id
    req.bought_at = now
    if req.ticket_id is not None:
        ticket = await db.get(Ticket, req.ticket_id)
        if ticket is not None:
            ticket_svc.log_event(
                db, ticket, "ration_bought", actor.user_id, {"ration_request_id": str(req.id)}, now
            )
    await notify.emit(
        db,
        "ration_bought",
        household,
        actor_user_id=actor.user_id,
        requester=req.raised_by,
        params={"items": _items_line(req)},
        data={"ration_request_id": req.id},
        now=now,
    )
    await db.flush()
    return req


# ---- suggestion (Should) ----------------------------------------------------------------------


async def suggest(
    db: AsyncSession, household: Household, days: int, *, now: datetime | None = None
) -> list[dict[str, Any]]:
    now = now or utcnow()
    today = menu_svc.local_today(household, now)
    end = today + timedelta(days=max(1, days))
    tickets = list(
        (
            await db.execute(
                select(Ticket)
                .where(
                    Ticket.household_id == household.id,
                    Ticket.date >= today,
                    Ticket.date < end,
                    Ticket.status.in_(list(ticket_svc.OPEN_STATUSES)),
                )
                .order_by(Ticket.due_at)
            )
        ).scalars()
    )
    pantry = await stock_svc.pantry(db, household.id)
    out: dict[uuid.UUID, dict[str, Any]] = {}
    for t in tickets:
        ids = menu_svc.parse_uuid_list(d.get("recipe_id") for d in t.dishes or [])
        recipes = await menu_svc.load_recipes(db, ids)
        for r in (recipes[i] for i in ids if i in recipes):
            for ri in r.ingredients:
                if ri.optional:
                    continue
                level = pantry.status(ri.ingredient_id)
                if level not in ("low", "out"):
                    continue
                entry = out.setdefault(
                    ri.ingredient_id,
                    {
                        "ingredient_id": ri.ingredient_id,
                        "name": ri.ingredient.name_en,
                        "name_hi": ri.ingredient.name_hi,
                        "level": level,
                        "unit": ri.ingredient.purchase_unit,
                        "needed_for": [],
                    },
                )
                ref = {"ticket_id": t.id, "date": t.date, "slot": t.slot}
                if ref not in entry["needed_for"]:
                    entry["needed_for"].append(ref)
    rows = {
        r["ingredient_id"]: r for r in await stock_svc.list_stock(db, household, materialise=False)
    }
    for iid, row in rows.items():
        if row["level"] in ("low", "out") and iid not in out:
            out[iid] = {
                "ingredient_id": iid,
                "name": row["name"],
                "name_hi": row["name_hi"],
                "level": row["level"],
                "unit": row["unit"],
                "needed_for": [],
            }
    return list(out.values())
