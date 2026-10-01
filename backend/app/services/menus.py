"""Day menus (FRD §5.6 + F-5.6-01, F-5.7-01): eaters, guests, servings, due time, coverage,
required items and the WhatsApp share text.

Rules:
- One menu per (household, date, slot) (FR-P1); adding the same dish twice is ignored.
- Eaters default to all active members, then to what was last chosen for the same slot and
  weekday (``Household.eater_defaults["slot:weekday"]``).
- Servings are adult-equivalents: adult 1.0, kid 0.5; guests the same (F-5.6-01).
- Coverage: every eater has at least one dish that is not "no" for them; guests are one
  virtual eater with the guest diet, or the strictest diet among the eaters.
- Due time defaults per slot (08:30, 13:30, 20:30, tiffin 07:30, shaam 17:30), overridable per
  household in ``slot_defaults[slot]["due"]`` and per menu.
- Required items: ingredients of the dishes, merged; status via a :class:`StockLookup`
  (pantry levels from ``app.services.stock``: in | low | out, untracked when no Staple row).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, Protocol
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import AppError, NotFound
from app.engine import EaterView, FitStatus, Summary, summarize
from app.models import (
    Cook,
    Diet,
    Household,
    Member,
    Menu,
    MenuDish,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
)
from app.services.catalogue import eater_view, recipe_view
from app.services.labels import day_label, slot_label, time_label

DEFAULT_DUE: dict[str, str] = {
    "nashta": "08:30",
    "lunch": "13:30",
    "dinner": "20:30",
    "tiffin": "07:30",
    "shaam": "17:30",
}
ADULT = Decimal("1.0")
KID = Decimal("0.5")
GUEST_NAME = "Mehmaan"
GUEST_DIETS: dict[str, Diet] = {"veg": Diet.veg, "jain": Diet.jain, "non_veg": Diet.non_veg}
# Strictest first: guests default to the strictest diet present among the eaters.
DIET_STRICTNESS: tuple[Diet, ...] = (
    Diet.jain,
    Diet.no_onion_garlic,
    Diet.veg,
    Diet.eggetarian,
    Diet.pescatarian,
    Diet.non_veg,
)


# ---- due time ----------------------------------------------------------------------------


def slot_due_time(household: Household, slot: str) -> time:
    raw = (household.slot_defaults or {}).get(slot, {})
    value = raw.get("due") if isinstance(raw, Mapping) else None
    try:
        return time.fromisoformat(str(value or DEFAULT_DUE.get(slot, "13:30")))
    except ValueError:
        return time.fromisoformat(DEFAULT_DUE.get(slot, "13:30"))


def default_due_at(household: Household, day: date, slot: str) -> datetime:
    tz = ZoneInfo(household.timezone or "Asia/Kolkata")
    return datetime.combine(day, slot_due_time(household, slot), tzinfo=tz)


def local_today(household: Household, now: datetime) -> date:
    return now.astimezone(ZoneInfo(household.timezone or "Asia/Kolkata")).date()


# ---- eaters, guests, servings ------------------------------------------------------------


def eater_key(slot: str, day: date) -> str:
    return f"{slot}:{day.weekday()}"


def default_eater_ids(
    household: Household, members: Sequence[Member], slot: str, day: date
) -> list[str]:
    active = [str(m.id) for m in members]
    remembered = (household.eater_defaults or {}).get(eater_key(slot, day))
    if isinstance(remembered, list):
        kept = [i for i in remembered if i in set(active)]
        if kept:
            return kept
    return active


def normalise_guests(raw: Mapping[str, Any] | None) -> dict[str, Any]:
    raw = raw or {}
    diet = raw.get("diet")
    return {
        "adults": max(0, int(raw.get("adults") or 0)),
        "kids": max(0, int(raw.get("kids") or 0)),
        "diet": diet if diet in GUEST_DIETS else None,
    }


def compute_servings(eaters: Iterable[Member], guests: Mapping[str, Any]) -> Decimal:
    total = sum((KID if m.is_kid else ADULT for m in eaters), Decimal("0"))
    total += ADULT * int(guests.get("adults") or 0) + KID * int(guests.get("kids") or 0)
    return total.quantize(Decimal("0.01"))


def strictest_diet(diets: Iterable[Diet]) -> Diet:
    present = set(diets)
    for d in DIET_STRICTNESS:
        if d in present:
            return d
    return Diet.veg


def guest_view(guests: Mapping[str, Any], eaters: Sequence[Member]) -> EaterView | None:
    if int(guests.get("adults") or 0) + int(guests.get("kids") or 0) <= 0:
        return None
    diet = GUEST_DIETS.get(str(guests.get("diet"))) or strictest_diet(m.diet for m in eaters)
    return EaterView(id="guests", name=GUEST_NAME, diet=diet)


def eater_ref(m: Member) -> dict[str, Any]:
    return {"member_id": str(m.id), "name": m.name, "colour": m.colour, "is_kid": m.is_kid}


# ---- coverage ------------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Coverage:
    all_covered: bool
    uncovered: tuple[str, ...]


def coverage(summaries: Sequence[Summary], eaters: Sequence[EaterView]) -> Coverage:
    """FR-P2 on eaters: each eater needs at least one dish that is not a "no" for them."""
    uncovered = []
    for e in eaters:
        ok = any(
            f.eater_id == e.id and f.fit.status != FitStatus.no for s in summaries for f in s.fits
        )
        if not ok:
            uncovered.append(e.name)
    return Coverage(all_covered=not uncovered, uncovered=tuple(uncovered))


def summary_dict(s: Summary) -> dict[str, Any]:
    """Same keys as ``SummaryOut`` (the RecipeCard summary)."""
    return {
        "badge": s.badge,
        "label_key": s.label_key,
        "label_params": dict(s.label_params),
        "note_key": s.note_key,
        "note_params": dict(s.note_params),
        "can": s.can,
        "perfect": s.perfect,
        "n": s.n,
    }


# ---- stock ----------------------------------------------------------------------------------


class StockLookup(Protocol):
    """in | low | out for tracked staples, untracked otherwise (``stock.PantryStock``)."""

    def status(self, ingredient_id: uuid.UUID) -> str: ...


async def stock_lookup(db: AsyncSession, household: Household) -> StockLookup:
    """Phase 6: pantry levels (F-5.6-04: read at render time, never stored on the ticket)."""
    from app.services.stock import pantry

    return await pantry(db, household.id)


def required_items(recipes: Sequence[Recipe], stock: StockLookup) -> list[dict[str, Any]]:
    """Merged ingredients of the dishes (optional ones skipped), in recipe order."""
    seen: dict[uuid.UUID, dict[str, Any]] = {}
    for r in recipes:
        for ri in sorted(r.ingredients, key=lambda x: x.sort_order):
            if ri.optional or ri.ingredient_id in seen:
                continue
            name = ri.ingredient.name_en if ri.ingredient is not None else ri.display_text
            seen[ri.ingredient_id] = {
                "ingredient_id": str(ri.ingredient_id),
                "display_text": name or "",
                "status": stock.status(ri.ingredient_id),
            }
    return list(seen.values())


# ---- loading ----------------------------------------------------------------------------------


async def active_members(db: AsyncSession, household: Household) -> list[Member]:
    stmt = select(Member).where(Member.household_id == household.id, Member.archived_at.is_(None))
    return list((await db.execute(stmt.order_by(Member.created_at, Member.id))).scalars())


async def load_recipes(db: AsyncSession, ids: Sequence[uuid.UUID]) -> dict[uuid.UUID, Recipe]:
    if not ids:
        return {}
    stmt = (
        select(Recipe)
        .where(Recipe.id.in_(list(ids)))
        .options(selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient))
    )
    return {r.id: r for r in (await db.execute(stmt)).scalars()}


async def menu_dish_ids(db: AsyncSession, menu: Menu) -> list[uuid.UUID]:
    rows = await db.execute(
        select(MenuDish.recipe_id).where(MenuDish.menu_id == menu.id).order_by(MenuDish.sort_order)
    )
    return list(rows.scalars())


def parse_uuid_list(values: Iterable[Any]) -> list[uuid.UUID]:
    out: list[uuid.UUID] = []
    for v in values:
        try:
            out.append(v if isinstance(v, uuid.UUID) else uuid.UUID(str(v)))
        except ValueError:
            continue
    return list(dict.fromkeys(out))


# ---- the menu view ------------------------------------------------------------------------------


@dataclass
class MenuPlan:
    """Everything derived from a menu: shared by the Menu response, confirm and share text."""

    dishes: list[dict[str, Any]]
    recipes: list[Recipe]
    eaters: list[Member]
    guests: dict[str, Any]
    servings: Decimal
    coverage: Coverage
    required_items: list[dict[str, Any]]
    extras: dict[str, Any] = field(default_factory=dict)

    def eater_refs(self) -> list[dict[str, Any]]:
        return [eater_ref(m) for m in self.eaters]


async def plan_for(
    db: AsyncSession,
    household: Household,
    recipe_ids: Sequence[uuid.UUID],
    eater_ids: Sequence[str],
    guests: Mapping[str, Any],
    day: date | None = None,
) -> MenuPlan:
    members = await active_members(db, household)
    by_id = {str(m.id): m for m in members}
    eaters = [by_id[i] for i in eater_ids if i in by_id]
    g = normalise_guests(guests)
    views = [eater_view(m, day=day) for m in eaters]
    gv = guest_view(g, eaters)
    if gv is not None:
        views.append(gv)
    recipes_by_id = await load_recipes(db, recipe_ids)
    recipes = [recipes_by_id[i] for i in recipe_ids if i in recipes_by_id]
    summaries = [summarize(views, recipe_view(r)) for r in recipes]
    dishes = [
        {
            "recipe_id": str(r.id),
            "name": r.name,
            "colour": r.colour,
            "image_url": r.image_url,
            "mins": r.mins,
            "summary": summary_dict(s),
        }
        for r, s in zip(recipes, summaries, strict=True)
    ]
    return MenuPlan(
        dishes=dishes,
        recipes=recipes,
        eaters=eaters,
        guests=g,
        servings=compute_servings(eaters, g),
        coverage=coverage(summaries, views),
        required_items=required_items(recipes, await stock_lookup(db, household)),
    )


async def menu_plan(db: AsyncSession, household: Household, menu: Menu) -> MenuPlan:
    return await plan_for(
        db,
        household,
        await menu_dish_ids(db, menu),
        list(menu.eaters or []),
        menu.guests or {},
        day=menu.date,
    )


def assignee_ref(cook: Cook | None) -> dict[str, Any] | None:
    if cook is None:
        return None
    return {"cook_id": str(cook.id), "name": cook.name or "", "kind": str(cook.kind)}


async def menu_view(db: AsyncSession, household: Household, menu: Menu) -> dict[str, Any]:
    plan = await menu_plan(db, household, menu)
    cook = await db.get(Cook, menu.assignee_cook_id) if menu.assignee_cook_id else None
    if cook is not None and cook.removed_at is not None:
        cook = None
    return {
        "id": menu.id,
        "date": menu.date,
        "slot": menu.slot,
        "dishes": plan.dishes,
        "eaters": plan.eater_refs(),
        "guests": plan.guests,
        "servings": float(menu.servings if menu.servings else plan.servings),
        "due_at": menu.due_at,
        "assignee": assignee_ref(cook),
        "coverage": {
            "all_covered": plan.coverage.all_covered,
            "uncovered": list(plan.coverage.uncovered),
        },
        "required_items": plan.required_items,
        "ticket_id": menu.ticket_id,
        "notes": menu.notes,
        "version": menu.version,
    }


# ---- mutations ------------------------------------------------------------------------------


async def get_menu(db: AsyncSession, household: Household, menu_id: uuid.UUID) -> Menu:
    menu = await db.get(Menu, menu_id)
    if menu is None or menu.household_id != household.id:
        raise NotFound()
    return menu


async def find_menu(db: AsyncSession, household: Household, day: date, slot: str) -> Menu | None:
    stmt = select(Menu).where(
        Menu.household_id == household.id, Menu.date == day, Menu.slot == slot
    )
    return (await db.execute(stmt)).scalar_one_or_none()


async def primary_cook(db: AsyncSession, household: Household) -> Cook | None:
    stmt = select(Cook).where(
        Cook.household_id == household.id, Cook.is_primary.is_(True), Cook.removed_at.is_(None)
    )
    return (await db.execute(stmt.limit(1))).scalar_one_or_none()


async def get_or_create_menu(db: AsyncSession, household: Household, day: date, slot: str) -> Menu:
    menu = await find_menu(db, household, day, slot)
    if menu is not None:
        return menu
    members = await active_members(db, household)
    eaters = default_eater_ids(household, members, slot, day)
    guests = normalise_guests(None)
    primary = await primary_cook(db, household)
    by_id = {str(m.id): m for m in members}
    menu = Menu(
        household_id=household.id,
        date=day,
        slot=slot,
        eaters=eaters,
        guests=guests,
        servings=compute_servings([by_id[i] for i in eaters], guests),
        due_at=default_due_at(household, day, slot),
        # F-5.6-02: the assignee is pre-filled from the primary cook, editable.
        assignee_cook_id=primary.id if primary else None,
        version=1,
    )
    db.add(menu)
    await db.flush()
    return menu


async def set_dishes(db: AsyncSession, menu: Menu, recipe_ids: Sequence[uuid.UUID]) -> bool:
    """Replace the dish list (duplicates ignored). Unknown / unpublished recipes are a 422."""
    ids = list(dict.fromkeys(recipe_ids))
    if ids:
        found = set(
            (
                await db.execute(
                    select(Recipe.id).where(
                        Recipe.id.in_(ids), Recipe.status == RecipeStatus.published
                    )
                )
            ).scalars()
        )
        missing = [str(i) for i in ids if i not in found]
        if missing:
            raise AppError(
                "unknown_recipe",
                "Some dishes are not available.",
                "Kuch dishes uplabdh nahi hain.",
                status_code=422,
                details={"recipe_ids": missing},
            )
    current = await menu_dish_ids(db, menu)
    if current == ids:
        return False
    existing = (await db.execute(select(MenuDish).where(MenuDish.menu_id == menu.id))).scalars()
    for row in existing:
        await db.delete(row)
    await db.flush()
    db.add_all(MenuDish(menu_id=menu.id, recipe_id=rid, sort_order=i) for i, rid in enumerate(ids))
    return True


async def patch_menu(
    db: AsyncSession, household: Household, menu: Menu, changes: Mapping[str, Any]
) -> bool:
    """Apply a PATCH. Keys absent from ``changes`` are untouched; explicit None clears
    assignee/notes. Remembers eaters per (slot, weekday)."""
    members = await active_members(db, household)
    by_id = {str(m.id): m for m in members}
    changed = False
    if "eaters" in changes and changes["eaters"] is not None:
        ids = [str(i) for i in parse_uuid_list(changes["eaters"])]
        unknown = [i for i in ids if i not in by_id]
        if unknown:
            raise NotFound(details={"member_ids": unknown})
        if ids != list(menu.eaters or []):
            menu.eaters = ids
            changed = True
        defaults = dict(household.eater_defaults or {})
        defaults[eater_key(menu.slot, menu.date)] = ids
        household.eater_defaults = defaults
    if "guests" in changes and changes["guests"] is not None:
        g = normalise_guests(changes["guests"])
        if g != (menu.guests or {}):
            menu.guests = g
            changed = True
    if "due_at" in changes and changes["due_at"] is not None and changes["due_at"] != menu.due_at:
        due = changes["due_at"]
        tz = ZoneInfo(household.timezone or "Asia/Kolkata")
        if due.astimezone(tz).date() != menu.date:
            # The ticket's date drives "today / tomorrow", reminders and read-only rules.
            raise AppError(
                "due_at_wrong_day",
                "The due time must be on the menu's day.",
                "Samay usi din ka hona chahiye jis din ka menu hai.",
                status_code=422,
                details={"date": menu.date.isoformat()},
            )
        menu.due_at = due
        changed = True
    if "assignee_cook_id" in changes:
        cook_id = changes["assignee_cook_id"]
        if cook_id is not None:
            cook = await db.get(Cook, cook_id)
            if cook is None or cook.household_id != household.id or cook.removed_at is not None:
                raise NotFound("cook_not_found")
        if cook_id != menu.assignee_cook_id:
            menu.assignee_cook_id = cook_id
            changed = True
    if "notes" in changes and changes["notes"] != menu.notes:
        menu.notes = changes["notes"]
        changed = True
    if changes.get("servings") is not None:
        # Explicit override (e.g. "cook for 6"); later eater/guest edits recompute it.
        value = Decimal(str(changes["servings"])).quantize(Decimal("0.01"))
        if value != menu.servings:
            menu.servings = value
            changed = True
    elif changed:
        menu.servings = compute_servings(
            [by_id[i] for i in menu.eaters or [] if i in by_id], menu.guests or {}
        )
    return changed


def bump(menu: Menu) -> None:
    menu.version = (menu.version or 0) + 1


# ---- share text ------------------------------------------------------------------------------


def _fmt_servings(value: Decimal | float) -> str:
    d = Decimal(str(value)).normalize()
    return f"{d:f}"


def share_text(
    household: Household,
    *,
    day: date,
    slot: str,
    due_at: datetime,
    dishes: Sequence[Mapping[str, Any]],
    eaters: Sequence[Mapping[str, Any]],
    guests: Mapping[str, Any],
    servings: Decimal | float,
    notes: str | None,
    items: Sequence[Mapping[str, Any]],
    assignee_name: str | None = None,
) -> str:
    """WhatsApp-ready Hinglish message (FR-P4, F-5.6-03): readable without the app."""
    lines = [f"*{slot_label(slot)} - {day_label(day)}*"]
    if assignee_name:
        lines.append(f"{assignee_name}, namaste.")
    lines.append(f"Kab tak: {time_label(due_at, household.timezone)}")
    lines.append("")
    lines.append("*Kya banana hai:*")
    if dishes:
        lines.extend(f"{i}. {d.get('name', '')}" for i, d in enumerate(dishes, 1))
    else:
        lines.append("(abhi koi dish nahi)")
    lines.append("")
    who = ", ".join(str(e.get("name", "")) for e in eaters) or "-"
    n_guests = int(guests.get("adults") or 0) + int(guests.get("kids") or 0)
    if n_guests:
        who += f" + {n_guests} mehmaan"
    lines.append(f"Kaun kha raha hai: {who}")
    lines.append(f"Kitne logon ka: {_fmt_servings(servings)}")
    if notes:
        lines.append(f"Note: {notes}")
    if items:
        lines.append("")
        lines.append("*Saaman:*")
        lines.extend(f"- {it.get('display_text', '')}" for it in items)
    lines.append("")
    lines.append("- Banega app se")
    return "\n".join(lines)


async def menu_share_text(db: AsyncSession, household: Household, menu: Menu) -> str:
    plan = await menu_plan(db, household, menu)
    cook = await db.get(Cook, menu.assignee_cook_id) if menu.assignee_cook_id else None
    return share_text(
        household,
        day=menu.date,
        slot=menu.slot,
        due_at=menu.due_at,
        dishes=plan.dishes,
        eaters=plan.eater_refs(),
        guests=plan.guests,
        servings=menu.servings if menu.servings else plan.servings,
        notes=menu.notes,
        items=plan.required_items,
        assignee_name=cook.name if cook is not None else None,
    )
