"""Tickets (contract §Tickets, §Cook mode): list, read, transitions, edit, claim, item out
(+ the Phase 6 out-of-stock ladder and its resolve), messages, ratings (Phase 7) and the
recipe scaled to the ticket."""

from __future__ import annotations

import math
import uuid
from datetime import date, timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Query, status
from sqlalchemy import or_, select
from sqlalchemy.orm import selectinload

from app.api.catalogue import recipe_detail
from app.api.deps import DB, HouseholdContext, HouseholdCtx, IfMatch, check_version
from app.core.errors import AppError, NotFound
from app.core.security import utcnow
from app.models import (
    Cook,
    CookLoginMode,
    Member,
    Recipe,
    RecipeIngredient,
    Ticket,
    TicketMessage,
    TicketStatus,
    User,
)
from app.schemas_kitchen import (
    AudioOut,
    MessageIn,
    MessageOut,
    TicketOut,
    TicketPatch,
    TicketRecipeOut,
    TransitionIn,
)
from app.schemas_pantry import (
    RatingOut,
    RatingsIn,
    ResolveIn,
    TicketLadderOut,
    TicketRatingsOut,
)
from app.services import ladder as ladder_svc
from app.services import menus as menu_svc
from app.services import ratings as rating_svc
from app.services import tickets as ticket_svc

router = APIRouter(prefix="/tickets", tags=["tickets"])

MAX_SERVINGS = 60


def _parse_date(value: str | None, ctx: HouseholdContext) -> date | None:
    if value is None or value == "":
        return None
    today = menu_svc.local_today(ctx.household, utcnow())
    if value == "today":
        return today
    if value == "tomorrow":
        return today + timedelta(days=1)
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise AppError(
            "invalid_date", "Use YYYY-MM-DD.", "Tareekh YYYY-MM-DD mein dijiye.", status_code=422
        ) from exc


async def _my_cook_ids(db: DB, ctx: HouseholdContext) -> list[uuid.UUID]:
    """Tickets that are "mine": my own cook role, plus (admin) cooks run via admin (F-2-03)."""
    conds = [Cook.user_id == ctx.user.id]
    if ctx.actor.is_admin:
        conds.append(Cook.login_mode == CookLoginMode.via_admin)
        conds.append(Cook.user_id.is_(None))
    rows = await db.execute(
        select(Cook.id).where(Cook.household_id == ctx.household.id, or_(*conds))
    )
    return list(rows.scalars())


async def _get_visible(db: DB, ctx: HouseholdContext, ticket_id: uuid.UUID) -> Ticket:
    ticket = await ticket_svc.get_ticket(db, ctx.household, ticket_id)
    if ctx.cook_only and (ctx.cook is None or ticket.assignee_cook_id != ctx.cook.id):
        raise NotFound()  # a hired cook sees her own tickets only
    return ticket


async def _out(db: DB, ticket: Ticket, ctx: HouseholdContext) -> TicketOut:
    return TicketOut.model_validate(await ticket_svc.ticket_view(db, ticket, ctx.actor))


MAX_RANGE_DAYS = 31


@router.get("", response_model=list[TicketOut])
async def list_tickets(
    ctx: HouseholdCtx,
    db: DB,
    date: Annotated[str | None, Query(description="YYYY-MM-DD, or today | tomorrow")] = None,
    from_: Annotated[
        str | None, Query(alias="from", description="range start (YYYY-MM-DD | today)")
    ] = None,
    to: Annotated[str | None, Query(description="range end, inclusive (max 31 days)")] = None,
    status_: Annotated[
        str | None, Query(alias="status", description="comma-separated statuses")
    ] = None,
    mine: bool = False,
) -> list[TicketOut]:
    """Sorted by due_at. A cook-only login always gets ``mine=true``. ``date`` or a
    ``from``..``to`` range of at most 31 days is required (422 ``date_required`` /
    ``range_too_long``): the list is never the whole history."""
    stmt = select(Ticket).where(Ticket.household_id == ctx.household.id)
    day = _parse_date(date, ctx)
    if day is not None:
        stmt = stmt.where(Ticket.date == day)
    elif from_ is not None and to is not None:
        start, end = _parse_date(from_, ctx), _parse_date(to, ctx)
        assert start is not None and end is not None
        if end < start or (end - start).days >= MAX_RANGE_DAYS:
            raise AppError(
                "range_too_long",
                f"Use a range of at most {MAX_RANGE_DAYS} days.",
                f"Zyada se zyada {MAX_RANGE_DAYS} din ki range dijiye.",
                status_code=422,
            )
        stmt = stmt.where(Ticket.date >= start, Ticket.date <= end)
    else:
        raise AppError(
            "date_required",
            "Pass a date, or a from / to range.",
            "Tareekh ya from / to range dijiye.",
            status_code=422,
        )
    if status_:
        try:
            wanted = [TicketStatus(s.strip()) for s in status_.split(",") if s.strip()]
        except ValueError as exc:
            raise AppError(
                "invalid_status", "Unknown status.", "Ye status nahi hai.", status_code=422
            ) from exc
        stmt = stmt.where(Ticket.status.in_(wanted))
    if mine or ctx.cook_only:
        stmt = stmt.where(Ticket.assignee_cook_id.in_(await _my_cook_ids(db, ctx)))
    tickets = (await db.execute(stmt.order_by(Ticket.due_at, Ticket.id))).scalars()
    return [await _out(db, t, ctx) for t in tickets]


@router.get("/{ticket_id}", response_model=TicketOut)
async def get_ticket(ticket_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> TicketOut:
    return await _out(db, await _get_visible(db, ctx, ticket_id), ctx)


@router.post("/{ticket_id}/transitions", response_model=TicketOut)
async def post_transition(
    ticket_id: uuid.UUID, body: TransitionIn, ctx: HouseholdCtx, db: DB, if_match: IfMatch = None
) -> TicketOut:
    ticket = await _get_visible(db, ctx, ticket_id)
    check_version(if_match, ticket.version)
    await ticket_svc.transition(
        db,
        ctx.household,
        ticket,
        body.to,
        ctx.actor,
        reason=body.reason,
        note=body.note,
        assignee_cook_id=body.assignee_cook_id,
    )
    await db.commit()
    return await _out(db, ticket, ctx)


@router.patch("/{ticket_id}", response_model=TicketOut)
async def patch_ticket(
    ticket_id: uuid.UUID, body: TicketPatch, ctx: HouseholdCtx, db: DB, if_match: IfMatch = None
) -> TicketOut:
    ticket = await _get_visible(db, ctx, ticket_id)
    check_version(if_match, ticket.version)
    changes: dict[str, Any] = body.model_dump(exclude_unset=True)
    if "guests" in changes and body.guests is not None:
        changes["guests"] = body.guests.model_dump()
    await ticket_svc.edit(db, ctx.household, ticket, ctx.actor, changes)
    await db.commit()
    return await _out(db, ticket, ctx)


@router.post("/{ticket_id}/claim", response_model=TicketOut)
async def claim_ticket(
    ticket_id: uuid.UUID, ctx: HouseholdCtx, db: DB, if_match: IfMatch = None
) -> TicketOut:
    ticket = await _get_visible(db, ctx, ticket_id)
    check_version(if_match, ticket.version)
    await ticket_svc.claim(db, ctx.household, ticket, ctx.actor)
    await db.commit()
    return await _out(db, ticket, ctx)


@router.post("/{ticket_id}/items/{ingredient_id}/out", response_model=TicketLadderOut)
async def item_out(
    ticket_id: uuid.UUID, ingredient_id: uuid.UUID, ctx: HouseholdCtx, db: DB
) -> TicketLadderOut:
    """Marks the item Out (pantry too, if tracked) and returns the §5.9 ladder."""
    ticket = await _get_visible(db, ctx, ticket_id)
    ladder = await ladder_svc.mark_out(db, ctx.household, ticket, ingredient_id, ctx.actor)
    view = ladder.view()
    await db.commit()
    out = await ticket_svc.ticket_view(db, ticket, ctx.actor)
    return TicketLadderOut.model_validate({**out, "ladder": view})


@router.post("/{ticket_id}/stock-issue/resolve", response_model=TicketOut)
async def resolve_stock_issue(
    ticket_id: uuid.UUID, body: ResolveIn, ctx: HouseholdCtx, db: DB
) -> TicketOut:
    """skip | swap | change_dish. Creates an Approval when the caller cannot approve it
    herself (``ticket.stock_issues[].approval``); otherwise the change is applied now."""
    ticket = await _get_visible(db, ctx, ticket_id)
    await ladder_svc.resolve(
        db,
        ctx.household,
        ticket,
        ctx.actor,
        action=body.action,
        substitute_ingredient_id=body.substitute_ingredient_id,
        recipe_id=body.recipe_id,
        ingredient_id=body.ingredient_id,
    )
    await db.commit()
    return await _out(db, ticket, ctx)


# ---- ratings (Phase 7) --------------------------------------------------------------------


async def _ratings_out(db: DB, ticket: Ticket, ctx: HouseholdContext) -> TicketRatingsOut:
    names = await rating_svc.member_names(db, ctx.household)
    rows = await rating_svc.ticket_ratings(db, ticket)
    return TicketRatingsOut(
        ticket_id=ticket.id,
        rated_at=ticket.rated_at,
        ratings=[
            RatingOut.model_validate(rating_svc.rating_view(r, ctx.actor, names)) for r in rows
        ],
    )


@router.post("/{ticket_id}/ratings", response_model=TicketOut)
async def rate_ticket(
    ticket_id: uuid.UUID, body: RatingsIn, ctx: HouseholdCtx, db: DB
) -> TicketOut:
    """Upsert per (recipe, member); the first rating sets ``rated_at``. Returns the Ticket;
    ``GET .../ratings`` lists the ratings (names masked per F-5.10-01)."""
    ticket = await _get_visible(db, ctx, ticket_id)
    await rating_svc.rate(
        db, ctx.household, ticket, ctx.actor, [r.model_dump() for r in body.ratings]
    )
    await db.commit()
    return await _out(db, ticket, ctx)


@router.get("/{ticket_id}/ratings", response_model=TicketRatingsOut)
async def get_ticket_ratings(ticket_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> TicketRatingsOut:
    ticket = await _get_visible(db, ctx, ticket_id)
    return await _ratings_out(db, ticket, ctx)


async def _message_out(db: DB, messages: list[TicketMessage], ticket: Ticket) -> list[MessageOut]:
    cook = await ticket_svc.ticket_cook(db, ticket)
    ids = {m.author_user_id for m in messages if m.author_user_id}
    names: dict[uuid.UUID, str | None] = {}
    if ids:
        rows = await db.execute(select(User.id, User.name).where(User.id.in_(ids)))
        names = {r[0]: r[1] for r in rows.all()}
    out = []
    for m in messages:
        is_cook = (
            cook is not None and m.author_user_id is not None and m.author_user_id == cook.user_id
        )
        name = (cook.name if is_cook and cook is not None else None) or (
            names.get(m.author_user_id) if m.author_user_id else None
        )
        out.append(
            MessageOut.model_validate(
                {
                    "id": m.id,
                    "text": m.text,
                    "author": {
                        "user_id": m.author_user_id,
                        "name": name or ("Cook" if is_cook else "Ghar se"),
                        "role": "cook" if is_cook else "family",
                    },
                    "created_at": m.created_at,
                }
            )
        )
    return out


@router.get("/{ticket_id}/messages", response_model=list[MessageOut])
async def list_messages(ticket_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> list[MessageOut]:
    ticket = await _get_visible(db, ctx, ticket_id)
    rows = list(
        (
            await db.execute(
                select(TicketMessage)
                .where(TicketMessage.ticket_id == ticket.id)
                .order_by(TicketMessage.created_at, TicketMessage.id)
            )
        ).scalars()
    )
    return await _message_out(db, rows, ticket)


@router.post(
    "/{ticket_id}/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED
)
async def post_message(
    ticket_id: uuid.UUID, body: MessageIn, ctx: HouseholdCtx, db: DB
) -> MessageOut:
    ticket = await _get_visible(db, ctx, ticket_id)
    msg = await ticket_svc.post_message(db, ctx.household, ticket, ctx.actor, body.text.strip())
    await db.commit()
    return (await _message_out(db, [msg], ticket))[0]


@router.get("/{ticket_id}/recipes/{recipe_id}", response_model=TicketRecipeOut)
async def ticket_recipe(
    ticket_id: uuid.UUID,
    recipe_id: uuid.UUID,
    ctx: HouseholdCtx,
    db: DB,
    servings: Annotated[int | None, Query(ge=1, le=MAX_SERVINGS)] = None,
) -> TicketRecipeOut:
    """K5: a dish of this ticket, scaled to the ticket's servings (rounded up)."""
    ticket = await _get_visible(db, ctx, ticket_id)
    if str(recipe_id) not in {str(d.get("recipe_id")) for d in ticket.dishes or []}:
        raise NotFound("recipe_not_in_ticket")
    recipe = (
        await db.execute(
            select(Recipe)
            .where(Recipe.id == recipe_id)
            .options(selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient))
        )
    ).scalar_one_or_none()
    if recipe is None:
        raise NotFound()
    ids = menu_svc.parse_uuid_list(e.get("member_id") for e in ticket.eaters or [])
    members = list(
        (await db.execute(select(Member).where(Member.id.in_(ids)))).scalars() if ids else []
    )
    wanted = servings or max(1, math.ceil(float(ticket.servings or 0)))
    detail = recipe_detail(recipe, members, wanted)
    if ctx.cook_only:
        # F-5.7-05: no member health/diet reasons in any hired-cook response.
        detail.fits = []
    steps = detail.steps_hi or detail.steps_en
    return TicketRecipeOut(**detail.model_dump(), audio=AudioOut(steps_hi=[None for _ in steps]))
