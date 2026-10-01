"""Day menus (contract §Menus): read, set dishes, patch eaters/guests/due/assignee/notes,
confirm into a ticket, share text."""

from __future__ import annotations

import uuid
from datetime import date

from fastapi import APIRouter
from sqlalchemy import select

from app.api.deps import DB, HouseholdCtx, IfMatch, check_version
from app.core.errors import AppError, NotFound
from app.models import MealSlot, Menu
from app.permissions import Action
from app.schemas_kitchen import (
    ConfirmOut,
    MenuDishesIn,
    MenuOut,
    MenuPatch,
    ShareTextOut,
    TicketOut,
)
from app.services import menus as menu_svc
from app.services import tickets as ticket_svc

router = APIRouter(prefix="/menus", tags=["menus"])


def _slot(value: str) -> str:
    try:
        return MealSlot(value).value
    except ValueError as exc:
        raise AppError(
            "invalid_slot", "Unknown meal slot.", "Ye meal slot nahi hai.", status_code=422
        ) from exc


@router.get("", response_model=MenuOut | list[MenuOut])
async def get_menus(
    ctx: HouseholdCtx, db: DB, date: date, slot: str | None = None
) -> MenuOut | list[MenuOut]:
    """``?date=&slot=`` -> that Menu (404 if none); ``?date=`` -> the day's menus."""
    if slot is not None:
        menu = await menu_svc.find_menu(db, ctx.household, date, _slot(slot))
        if menu is None:
            raise NotFound("menu_not_found")
        return MenuOut.model_validate(await menu_svc.menu_view(db, ctx.household, menu))
    menus = (
        await db.execute(
            select(Menu).where(Menu.household_id == ctx.household.id, Menu.date == date)
        )
    ).scalars()
    order = {s.value: i for i, s in enumerate(MealSlot)}
    return [
        MenuOut.model_validate(await menu_svc.menu_view(db, ctx.household, m))
        for m in sorted(menus, key=lambda m: order.get(m.slot, 99))
    ]


@router.get("/{menu_id}", response_model=MenuOut)
async def get_menu(menu_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> MenuOut:
    """One menu by id (``required_items[].status`` from the pantry, Phase 6)."""
    menu = await menu_svc.get_menu(db, ctx.household, menu_id)
    return MenuOut.model_validate(await menu_svc.menu_view(db, ctx.household, menu))


@router.put("/{day}/{slot}/dishes", response_model=MenuOut)
async def put_dishes(
    day: date, slot: str, body: MenuDishesIn, ctx: HouseholdCtx, db: DB, if_match: IfMatch = None
) -> MenuOut:
    ctx.require(Action.edit_day_menu)
    menu = await menu_svc.get_or_create_menu(db, ctx.household, day, _slot(slot))
    check_version(if_match, menu.version)
    if await menu_svc.set_dishes(db, menu, body.recipe_ids):
        menu_svc.bump(menu)
    await db.commit()
    return MenuOut.model_validate(await menu_svc.menu_view(db, ctx.household, menu))


@router.patch("/{menu_id}", response_model=MenuOut)
async def patch_menu(
    menu_id: uuid.UUID, body: MenuPatch, ctx: HouseholdCtx, db: DB, if_match: IfMatch = None
) -> MenuOut:
    ctx.require(Action.edit_day_menu)
    menu = await menu_svc.get_menu(db, ctx.household, menu_id)
    check_version(if_match, menu.version)
    changes = body.model_dump(exclude_unset=True)
    if await menu_svc.patch_menu(db, ctx.household, menu, changes):
        menu_svc.bump(menu)
    await db.commit()
    return MenuOut.model_validate(await menu_svc.menu_view(db, ctx.household, menu))


@router.post("/{menu_id}/confirm", response_model=ConfirmOut)
async def confirm_menu(
    menu_id: uuid.UUID, ctx: HouseholdCtx, db: DB, if_match: IfMatch = None
) -> ConfirmOut:
    """Creates the ticket (Idempotency-Key replays the first response)."""
    menu = await menu_svc.get_menu(db, ctx.household, menu_id)
    check_version(if_match, menu.version)
    ticket = await ticket_svc.confirm(db, ctx.household, menu, ctx.actor)
    menu_svc.bump(menu)
    text = await menu_svc.menu_share_text(db, ctx.household, menu)
    await db.commit()
    view = await ticket_svc.ticket_view(db, ticket, ctx.actor)
    return ConfirmOut(ticket=TicketOut.model_validate(view), share_text=text)


@router.get("/{menu_id}/share-text", response_model=ShareTextOut)
async def share_text(menu_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> ShareTextOut:
    menu = await menu_svc.get_menu(db, ctx.household, menu_id)
    return ShareTextOut(text=await menu_svc.menu_share_text(db, ctx.household, menu))
