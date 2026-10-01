"""``python -m app.cli demo-day``: today's lunch menu + ticket for the demo household, so the
cook app (Ramesh ji, +919999999990) has something to accept right after ``seed``. Phase 6:
dahi is marked Out on the ticket (gatte needs it) so the out-of-stock ladder can be demoed."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Household,
    HouseholdMembership,
    Ingredient,
    MembershipStatus,
    Recipe,
    RecipeStatus,
    Ticket,
    User,
)
from app.services import menus as menu_svc
from app.services import tickets as ticket_svc
from app.services.importer import DEV_ADMIN_PHONE

DEMO_LUNCH = ("gatte", "daltadka", "bhindi", "khichdi", "palak")


@dataclass
class DemoDay:
    menu_id: str
    ticket_id: str
    status: str
    share_text: str
    ladder_step: str | None = None


async def create_demo_day(
    db: AsyncSession, *, admin_phone: str = DEV_ADMIN_PHONE, now: datetime | None = None
) -> DemoDay:
    from app.api.deps import build_actor
    from app.models.base import utcnow

    now = now or utcnow()
    user = (await db.execute(select(User).where(User.phone == admin_phone))).scalar_one_or_none()
    if user is None:
        raise SystemExit(f"no user {admin_phone}: run `python -m app.cli seed` first")
    membership = (
        await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.user_id == user.id,
                HouseholdMembership.status == MembershipStatus.active,
            )
        )
    ).scalar_one()
    household = await db.get(Household, membership.household_id)
    assert household is not None
    day = menu_svc.local_today(household, now)
    menu = await menu_svc.get_or_create_menu(db, household, day, "lunch")
    existing = await db.get(Ticket, menu.ticket_id) if menu.ticket_id else None
    if existing is None or existing.status == "cancelled":
        recipes = {
            r.slug: r.id
            for r in (
                await db.execute(
                    select(Recipe).where(
                        Recipe.slug.in_(DEMO_LUNCH), Recipe.status == RecipeStatus.published
                    )
                )
            ).scalars()
        }
        ids = [recipes[s] for s in DEMO_LUNCH if s in recipes][:2]
        if await menu_svc.set_dishes(db, menu, ids):
            menu_svc.bump(menu)
        actor = build_actor(user, membership, household, None)
        existing = await ticket_svc.confirm(db, household, menu, actor, now=now)
        menu_svc.bump(menu)
    text = await menu_svc.menu_share_text(db, household, menu)
    step = await _dahi_out(db, household, existing, user, membership, now)
    await db.commit()
    return DemoDay(
        menu_id=str(menu.id),
        ticket_id=str(existing.id),
        status=str(existing.status),
        share_text=text,
        ladder_step=step,
    )


DEMO_OUT = "curd"


async def _dahi_out(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    admin: User,
    admin_membership: HouseholdMembership,
    now: datetime,
) -> str | None:
    """Mark dahi Out on today's ticket as its cook (the admin acts for a cook who has not
    logged in yet). Idempotent: an open dahi issue is left alone."""
    from app.api.deps import build_actor
    from app.services import ladder

    curd = (await db.execute(select(Ingredient).where(Ingredient.slug == DEMO_OUT))).scalar()
    if curd is None or ticket.status not in ticket_svc.OPEN_STATUSES:
        return None
    if not any(i["ingredient_id"] == str(curd.id) for i in await _items(db, household, ticket)):
        return None
    issue = await ladder.open_issue(db, ticket, curd.id)
    if issue is not None:
        return str(issue.step)
    cook = await ticket_svc.ticket_cook(db, ticket)
    actor = build_actor(admin, admin_membership, household, None)
    if cook is not None and cook.user_id is not None:
        cook_user = await db.get(User, cook.user_id)
        membership = (
            await db.execute(
                select(HouseholdMembership).where(
                    HouseholdMembership.user_id == cook.user_id,
                    HouseholdMembership.household_id == household.id,
                    HouseholdMembership.status == MembershipStatus.active,
                )
            )
        ).scalar_one_or_none()
        if cook_user is not None and membership is not None:
            actor = build_actor(cook_user, membership, household, cook.kind)
    result = await ladder.mark_out(db, household, ticket, curd.id, actor, now=now)
    return str(result.step)


async def _items(db: AsyncSession, household: Household, ticket: Ticket) -> list[dict[str, str]]:
    ids = menu_svc.parse_uuid_list(d.get("recipe_id") for d in ticket.dishes or [])
    recipes = await menu_svc.load_recipes(db, ids)
    return menu_svc.required_items(
        [recipes[i] for i in ids if i in recipes], await menu_svc.stock_lookup(db, household)
    )
