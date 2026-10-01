"""Ratings (FRD §5.10 as amended by F-5.10-01/04, §2.1 rate_meal / rate_for_profile_member /
see_named_ratings; contract Phase 7).

- ``POST /tickets/{id}/ratings``: upsert per (ticket, recipe, member); score 1..3; only on a
  ``completed`` ticket; ``Ticket.rated_at`` is set by the first rating. A user rates for her
  own profile (``rate_meal``) or, as a proxy, for a profile-only member (no login;
  ``rate_for_profile_member``). ``Household.ratings_enabled = false`` -> 409
  ``ratings_disabled``.
- Summary: per member average and count. A hired cook sees only the aggregate unless
  ``Household.show_names_to_cook``; an adult member sees names only for her own ratings
  (``see_named_ratings``).
- On completion (:func:`on_completed`): served history, auto-decrement, ``rate_prompt`` to
  the confirmer and the admin (the completer too: the prompt is not "about" her action).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, Forbidden
from app.models import (
    Household,
    HouseholdMembership,
    Member,
    MembershipStatus,
    Rating,
    Recipe,
    ServedHistory,
    Ticket,
    TicketStatus,
)
from app.models.base import utcnow
from app.permissions import Action, Actor, Resource, can
from app.services import menus as menu_svc
from app.services import notifications as notify
from app.services import stock as stock_svc
from app.services import tickets as ticket_svc

SCORES = {1: "bura", 2: "theek", 3: "bahut_accha"}
MASKED_NAME = "Ghar ka ek sadasya"


def ratings_disabled() -> Conflict:
    return Conflict(
        "ratings_disabled",
        "Ratings are turned off for this household.",
        "Is ghar mein rating band hai.",
    )


async def _profile_only(db: AsyncSession, household: Household) -> set[uuid.UUID]:
    """Members without an active login (kids, elders): proxy ratings are allowed for them."""
    linked = set(
        (
            await db.execute(
                select(HouseholdMembership.member_id).where(
                    HouseholdMembership.household_id == household.id,
                    HouseholdMembership.status == MembershipStatus.active,
                    HouseholdMembership.member_id.is_not(None),
                )
            )
        ).scalars()
    )
    members = (
        await db.execute(select(Member.id).where(Member.household_id == household.id))
    ).scalars()
    return {m for m in members if m not in linked}


async def rate(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    actor: Actor,
    items: Sequence[Mapping[str, Any]],
    *,
    now: datetime | None = None,
) -> list[Rating]:
    now = now or utcnow()
    if not household.ratings_enabled:
        raise ratings_disabled()
    if ticket.status != TicketStatus.completed:
        raise Conflict(
            "not_completed",
            "Rate after the meal is marked completed.",
            "Khaana complete hone ke baad rating dijiye.",
            details={"status": str(ticket.status)},
        )
    dish_ids = {str(d.get("recipe_id")) for d in ticket.dishes or []}
    eater_ids = {str(e.get("member_id")) for e in ticket.eaters or []}
    profile_only = await _profile_only(db, household)
    out: list[Rating] = []
    for it in items:
        recipe_id, member_id = it["recipe_id"], it["member_id"]
        if str(recipe_id) not in dish_ids or str(member_id) not in eater_ids:
            raise AppError(
                "not_on_ticket",
                "That dish or person is not on this meal.",
                "Ye dish ya vyakti is khaane mein nahi tha.",
                status_code=422,
                details={"recipe_id": str(recipe_id), "member_id": str(member_id)},
            )
        own = actor.member_id is not None and actor.member_id == member_id
        if own:
            allowed = can(actor, Action.rate_meal)
        else:
            allowed = member_id in profile_only and can(actor, Action.rate_for_profile_member)
        if not allowed:
            raise Forbidden(
                "not_your_rating",
                "You can rate for yourself or for a member without the app.",
                "Aap apni ya bina app wale sadasya ki rating de sakte hain.",
                details={"member_id": str(member_id)},
            )
        row = (
            await db.execute(
                select(Rating).where(
                    Rating.ticket_id == ticket.id,
                    Rating.recipe_id == recipe_id,
                    Rating.member_id == member_id,
                )
            )
        ).scalar_one_or_none()
        if row is None:
            row = Rating(
                household_id=household.id,
                ticket_id=ticket.id,
                recipe_id=recipe_id,
                member_id=member_id,
                created_at=now,
            )
            db.add(row)
        row.score = int(it["score"])
        row.note = it.get("note")
        row.rated_by_user_id = actor.user_id
        row.updated_at = now
        out.append(row)
    if ticket.rated_at is None and out:
        ticket.rated_at = now
        ticket_svc.log_event(db, ticket, "rated", actor.user_id, {"count": len(out)}, now)
    await db.flush()
    return out


async def ticket_ratings(db: AsyncSession, ticket: Ticket) -> list[Rating]:
    rows = await db.execute(
        select(Rating).where(Rating.ticket_id == ticket.id).order_by(Rating.created_at, Rating.id)
    )
    return list(rows.scalars())


def can_see_name(actor: Actor, member_id: uuid.UUID) -> bool:
    return can(actor, Action.see_named_ratings, Resource(owner_member_id=member_id))


def rating_view(r: Rating, actor: Actor, names: Mapping[uuid.UUID, str]) -> dict[str, Any]:
    named = can_see_name(actor, r.member_id)
    return {
        "id": r.id,
        "ticket_id": r.ticket_id,
        "recipe_id": r.recipe_id,
        "member_id": r.member_id if named else None,
        "member_name": names.get(r.member_id, "") if named else MASKED_NAME,
        "rated_by_user_id": r.rated_by_user_id if named else None,
        "score": r.score,
        "note": r.note,
        "created_at": r.created_at,
    }


async def member_names(db: AsyncSession, household: Household) -> dict[uuid.UUID, str]:
    rows = await db.execute(
        select(Member.id, Member.name).where(Member.household_id == household.id)
    )
    return {r[0]: r[1] for r in rows.all()}


async def summary(
    db: AsyncSession,
    household: Household,
    actor: Actor,
    *,
    recipe_id: uuid.UUID | None = None,
) -> list[dict[str, Any]]:
    """Per recipe: overall average and count, and per-member rows the caller may see by name.
    A hired cook without ``show_names_to_cook`` gets an empty ``members`` list (aggregate only)."""
    stmt = (
        select(Rating)
        .join(Ticket, Ticket.id == Rating.ticket_id)
        .where(Rating.household_id == household.id, Ticket.status == TicketStatus.completed)
    )
    if recipe_id is not None:
        stmt = stmt.where(Rating.recipe_id == recipe_id)
    rows = list((await db.execute(stmt)).scalars())
    names = await member_names(db, household)
    recipe_names = (
        {
            r.id: r.name
            for r in (
                await db.execute(select(Recipe).where(Recipe.id.in_({x.recipe_id for x in rows})))
            ).scalars()
        }
        if rows
        else {}
    )
    by_recipe: dict[uuid.UUID, list[Rating]] = defaultdict(list)
    for r in rows:
        by_recipe[r.recipe_id].append(r)
    out = []
    for rid, items in by_recipe.items():
        per_member: dict[uuid.UUID, list[int]] = defaultdict(list)
        for r in items:
            per_member[r.member_id].append(r.score)
        members = [
            {
                "member_id": mid,
                "name": names.get(mid, ""),
                "average": round(sum(s) / len(s), 2),
                "count": len(s),
            }
            for mid, s in per_member.items()
            if can_see_name(actor, mid)
        ]
        members.sort(key=lambda m: str(m["name"]))
        notes = [r.note for r in sorted(items, key=lambda x: x.created_at, reverse=True) if r.note]
        out.append(
            {
                "recipe_id": rid,
                "name": recipe_names.get(rid, ""),
                "average": round(sum(r.score for r in items) / len(items), 2),
                "count": len(items),
                "members": members,
                # Notes without names (F-5.10-01): the cook reads what to change.
                "notes": notes[:5],
            }
        )
    out.sort(key=lambda x: (-float(str(x["average"])), str(x["name"])))
    return out


# ---- completion hook -------------------------------------------------------------------------


async def on_completed(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    *,
    now: datetime | None = None,
) -> None:
    """Called once when a ticket reaches ``completed`` (API or "Khaana bana?" answer)."""
    now = now or utcnow()
    ids = menu_svc.parse_uuid_list(d.get("recipe_id") for d in ticket.dishes or [])
    existing = set(
        (
            await db.execute(
                select(ServedHistory.recipe_id).where(ServedHistory.ticket_id == ticket.id)
            )
        ).scalars()
    )
    for rid in ids:
        if rid not in existing:
            db.add(
                ServedHistory(
                    household_id=household.id, recipe_id=rid, ticket_id=ticket.id, served_at=now
                )
            )
    # Auto-decrement (Should): ingredients actually used, after swaps / skips.
    used: list[uuid.UUID] = []
    recipes = await menu_svc.load_recipes(db, ids)
    for d in ticket.dishes or []:
        r = recipes.get(uuid.UUID(str(d["recipe_id"])))
        if r is None:
            continue
        swapped = {
            s.get("from_ingredient_id"): s.get("to_ingredient_id") for s in d.get("swaps") or []
        }
        for ri in r.ingredients:
            if ri.optional:
                continue
            key = str(ri.ingredient_id)
            if key in swapped:
                if swapped[key]:
                    used.append(uuid.UUID(str(swapped[key])))
                continue
            used.append(ri.ingredient_id)
    changes = await stock_svc.auto_decrement(db, household, ticket, used, now=now)
    if changes:
        ticket_svc.log_event(
            db,
            ticket,
            "stock_decremented",
            None,
            {"items": [{"name": c.ingredient.name_en, "to": c.after} for c in changes]},
            now,
        )
        await stock_svc.notify_low(db, household, changes, actor_user_id=None, now=now)
    if household.ratings_enabled:
        eaters = ", ".join(str(e.get("name", "")) for e in ticket.eaters or []) or "sab"
        await notify.emit(
            db,
            "rate_prompt",
            household,
            ticket=ticket,
            params=ticket_svc.ticket_params(household, ticket, eaters=eaters),
            now=now,
        )
    await db.flush()
