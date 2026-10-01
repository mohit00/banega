"""Out-of-stock ladder (FRD §5.9 as amended by F-5.9-01/03/06, F-2-02/04; contract Phase 6).

On ``POST /tickets/{id}/items/{ingredient_id}/out`` the item is marked Out in the pantry (if
tracked), a ``TicketStockIssue`` is opened and the ladder is computed by the engine:

1. ``save_dish``: skip the item, when it is ``optional`` in every dish that uses it, or a
   "can be left out" rule exists (a ``SubstitutionRule`` with ``ratio = 0``, by convention
   ``to_ingredient_id = from_ingredient_id``). No approval.
2. ``swap``: substitutes from ``SubstitutionRule`` only (never invented), dropped when the
   substitute is Out, and re-checked by the engine for every eater (+ guests): a candidate
   that turns any eater's Fit/Tweak into a No (allergen, diet, dislike...) is removed.
   ``fit_after`` is the dish summary with the substitute.
3. ``change_dish``: the top 3 published recipes for the same slot whose tracked ingredients
   are all in/low (untracked = assumed available, F-5.9-06), never an allergen No for an
   eater, ranked by the engine with the learning / repetition / stock context.

``resolve`` creates an ``Approval``. §2.1 (``permissions.TABLE``) decides who may approve;
when the requester may approve her own action (admin, adult member, family cook, a hired
cook for swaps while ``Household.cook_can_approve_swaps``), the approval is written with
``auto=true`` and applied at once (F-2-04). Otherwise approvers are notified; the first
response wins (guarded UPDATE). After ``APPROVAL_TTL`` the worker marks it ``expired`` and
alerts the admin (``stock_issue_timeout``); the ticket keeps ``stock_issue_open``.

Every step appends a ``TicketEvent``.
"""

from __future__ import annotations

import dataclasses
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.engine import EaterView, FitStatus, RecipeView, Summary, rank, summarize
from app.models import (
    Approval,
    ApprovalDecision,
    ApprovalType,
    Diet,
    Household,
    Ingredient,
    IssueResolution,
    LadderStep,
    Member,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
    StockLevel,
    SubstitutionRule,
    Ticket,
    TicketStockIssue,
)
from app.models.base import utcnow
from app.permissions import Action, Actor, Resource, resolve_approval
from app.services import menus as menu_svc
from app.services import notifications as notify
from app.services import stock as stock_svc
from app.services import tickets as ticket_svc
from app.services.catalogue import eater_view, recipe_view
from app.services.refs import ref
from app.services.tagging import derive, facts_for

APPROVAL_TTL = timedelta(minutes=30)
ALTERNATIVES = 3
TICKET_APPROVALS: tuple[ApprovalType, ...] = (ApprovalType.swap, ApprovalType.change_dish)


# ---- engine glue ----------------------------------------------------------------------------


def swapped_view(recipe: Recipe, from_id: uuid.UUID, to: Ingredient | None) -> RecipeView:
    """The engine view of ``recipe`` with ``from_id`` replaced by ``to`` (None = left out).
    Diet and allergen flags are re-derived from the new ingredient list (F-6-06)."""
    base = recipe_view(recipe)
    ings: list[Ingredient] = []
    for ri in recipe.ingredients:
        if ri.ingredient_id == from_id:
            if to is not None and to not in ings:
                ings.append(to)
        elif ri.ingredient is not None:
            ings.append(ri.ingredient)
    d = derive(
        (facts_for(i) for i in ings),
        editorial_jain_safe=recipe.editorial_jain_safe,
        editorial_diet=recipe.editorial_diet,
        vrat_ok=recipe.vrat_ok,
    )
    old_refs = {str(from_id)}
    new_refs: set[str] = set()
    for ri in recipe.ingredients:
        if ri.ingredient_id == from_id and ri.ingredient is not None:
            old_refs.add(ri.ingredient.slug)
    if to is not None:
        new_refs = {str(to.id), to.slug}
    was_main = bool(old_refs & base.main_ingredients)

    def swap(refs: frozenset[str], add: bool) -> frozenset[str]:
        out = set(refs) - old_refs
        if add:
            out |= new_refs
        return frozenset(out)

    return dataclasses.replace(
        base,
        is_veg=d.is_veg,
        has_egg=d.has_egg,
        has_nonveg=d.has_nonveg,
        meat_types=frozenset(d.meat_types),
        jain_safe=d.jain_safe,
        has_onion_garlic=not d.no_onion_garlic,
        has_root_veg=d.has_root_veg,
        dairy_free=d.dairy_free,
        allergens=frozenset(d.allergens),
        main_ingredients=swap(base.main_ingredients, was_main),
        other_ingredients=swap(base.other_ingredients, not was_main),
        tracked_ingredients=swap(base.tracked_ingredients, bool(to is not None and to.trackable)),
    )


def introduces_no(before: Summary, after: Summary) -> list[str]:
    """Eaters (names) for whom ``after`` is a No while ``before`` was not."""
    was = {f.eater_id: f.fit.status for f in before.fits}
    return [
        f.name
        for f in after.fits
        if f.fit.status == FitStatus.no and was.get(f.eater_id) != FitStatus.no
    ]


def has_allergen_no(s: Summary) -> bool:
    return any(f.fit.status == FitStatus.no and f.fit.reason_key == "allergen" for f in s.fits)


# ---- context ---------------------------------------------------------------------------------


@dataclass
class TicketContext:
    ticket: Ticket
    recipes: list[Recipe]
    eaters: list[EaterView]
    pantry: stock_svc.PantryStock


async def ticket_context(db: AsyncSession, household: Household, ticket: Ticket) -> TicketContext:
    ids = menu_svc.parse_uuid_list(d.get("recipe_id") for d in ticket.dishes or [])
    by_id = await menu_svc.load_recipes(db, ids)
    member_ids = menu_svc.parse_uuid_list(e.get("member_id") for e in ticket.eaters or [])
    members = (
        list((await db.execute(select(Member).where(Member.id.in_(member_ids)))).scalars())
        if member_ids
        else []
    )
    order = {m: i for i, m in enumerate(member_ids)}
    members.sort(key=lambda m: order.get(m.id, 99))
    views = [eater_view(m, day=ticket.date) for m in members]
    gv = menu_svc.guest_view(ticket.guests or {}, members)
    if gv is not None:
        views.append(gv)
    return TicketContext(
        ticket=ticket,
        recipes=[by_id[i] for i in ids if i in by_id],
        eaters=views,
        pantry=await stock_svc.pantry(db, household.id),
    )


# ---- the ladder ------------------------------------------------------------------------------


@dataclass
class Ladder:
    issue: TicketStockIssue
    ingredient: Ingredient
    step: LadderStep
    skip: dict[str, Any]
    swaps: list[dict[str, Any]] = field(default_factory=list)
    alternatives: list[dict[str, Any]] = field(default_factory=list)
    replaces_recipe_id: uuid.UUID | None = None

    def view(self) -> dict[str, Any]:
        """All three steps' options; ``step`` is the first applicable one."""
        return {
            "step": str(self.step),
            "ingredient": _ing_ref(self.ingredient),
            "options": {
                "save_dish": self.skip,
                "swap": self.swaps,
                "change_dish": self.alternatives,
            },
            "issue_id": self.issue.id,
            "replaces_recipe_id": self.replaces_recipe_id,
        }


def _ing_ref(i: Ingredient) -> dict[str, Any]:
    return {"ingredient_id": i.id, "name": i.name_en, "name_hi": i.name_hi}


async def _rules(db: AsyncSession, ingredient_id: uuid.UUID) -> list[SubstitutionRule]:
    stmt = (
        select(SubstitutionRule)
        .where(
            SubstitutionRule.from_ingredient_id == ingredient_id,
            SubstitutionRule.is_active.is_(True),
        )
        .options(
            selectinload(SubstitutionRule.to_ingredient),
            selectinload(SubstitutionRule.from_ingredient),
        )
        .order_by(SubstitutionRule.created_at, SubstitutionRule.id)
    )
    return list((await db.execute(stmt)).scalars())


def _uses(recipe: Recipe, ingredient_id: uuid.UUID) -> list[RecipeIngredient]:
    return [ri for ri in recipe.ingredients if ri.ingredient_id == ingredient_id]


async def compute(
    db: AsyncSession,
    household: Household,
    ctx: TicketContext,
    ingredient: Ingredient,
    issue: TicketStockIssue,
    *,
    now: datetime | None = None,
) -> Ladder:
    affected = [r for r in ctx.recipes if _uses(r, ingredient.id)]
    rules = await _rules(db, ingredient.id)
    cuisines = {r.cuisine for r in affected}

    def in_scope(rule: SubstitutionRule) -> bool:
        return rule.cuisine_scope is None or rule.cuisine_scope in cuisines

    skip_rule = next(
        (
            x
            for x in rules
            if in_scope(x) and (x.ratio == 0 or x.to_ingredient_id == x.from_ingredient_id)
        ),
        None,
    )
    optional = bool(affected) and all(
        ri.optional for r in affected for ri in _uses(r, ingredient.id)
    )
    # Onion / garlic with a Jain or no-onion-garlic eater at the table: leaving it out makes
    # the dish fit more people, never fewer.
    jain = bool((ingredient.flags or {}).get("onion_garlic")) and any(
        e.diet in (Diet.jain, Diet.no_onion_garlic) for e in ctx.eaters
    )
    if not affected:
        reason = "not_used"
    elif optional:
        reason = "optional"
    elif jain:
        reason = "jain"
    elif skip_rule is not None:
        reason = "rule"
    else:
        reason = "required"
    skip = {
        "type": "skip",
        "ingredient": _ing_ref(ingredient),
        "ok": reason != "required",
        "reason": reason,
        "note_hi": skip_rule.note_hi if skip_rule is not None else None,
    }
    skip_ok = bool(skip["ok"])

    swaps: list[dict[str, Any]] = []
    for rule in rules:
        to = rule.to_ingredient
        if rule is skip_rule or to is None or to.id == ingredient.id or not in_scope(rule):
            continue
        if not to.is_active or not ctx.pantry.usable(to.id):
            continue
        fit_after: dict[str, Any] | None = None
        blocked: list[str] = []
        for r in affected:
            before = summarize(ctx.eaters, recipe_view(r))
            after = summarize(ctx.eaters, swapped_view(r, ingredient.id, to))
            blocked += introduces_no(before, after)
            if fit_after is None:
                fit_after = menu_svc.summary_dict(after)
        if blocked:
            continue  # O2: never introduces an allergen or a diet No for anybody at the table
        swaps.append(
            {
                "type": "swap",
                "substitute_ingredient_id": to.id,
                "name": to.name_en,
                "name_hi": to.name_hi,
                "ratio": float(rule.ratio),
                "note_hi": rule.note_hi,
                "note_en": rule.note_en,
                "stock": ctx.pantry.status(to.id),
                "fit_after": fit_after,
            }
        )

    replaces = next(
        (r for r in affected if not all(ri.optional for ri in _uses(r, ingredient.id))),
        affected[0] if affected else None,
    )
    alternatives = await _alternatives(db, household, ctx, replaces, now=now)

    if skip_ok:
        step = LadderStep.save_dish
    elif swaps:
        step = LadderStep.swap
    else:
        step = LadderStep.change_dish
    return Ladder(
        issue=issue,
        ingredient=ingredient,
        step=step,
        skip=skip,
        swaps=swaps,
        alternatives=alternatives,
        replaces_recipe_id=replaces.id if replaces is not None else None,
    )


async def _alternatives(
    db: AsyncSession,
    household: Household,
    ctx: TicketContext,
    replaces: Recipe | None,
    *,
    now: datetime | None = None,
) -> list[dict[str, Any]]:
    from app.api.catalogue import card_out
    from app.services import learning

    current = {r.id for r in ctx.recipes}
    stmt = (
        select(Recipe)
        .where(Recipe.status == RecipeStatus.published)
        .options(selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient))
    )
    pool: list[Recipe] = []
    for r in (await db.execute(stmt)).scalars():
        if r.id in current or ctx.ticket.slot not in (r.meal_slots or []):
            continue
        if any(not ri.optional and not ctx.pantry.usable(ri.ingredient_id) for ri in r.ingredients):
            continue  # only in/low stock (untracked assumed available)
        pool.append(r)
    if not pool:
        return []
    by_id = {str(r.id): r for r in pool}
    views = [recipe_view(r) for r in pool]
    score_ctx = await learning.score_context(
        db, household, menu_svc.local_today(household, now or utcnow())
    )
    ranking = rank(
        views,
        ctx.eaters,
        score_ctx,
        None,
        grid_size=len(views),
        max_per_category=len(views),
    )
    ordered = [ranking.pick, *ranking.tiles] if ranking.pick else []
    out: list[dict[str, Any]] = []
    for item in ordered:
        if item is None or has_allergen_no(item.summary):
            continue
        out.append(card_out(by_id[item.recipe.id], item.summary).model_dump(mode="json"))
        if len(out) >= ALTERNATIVES:
            break
    return out


# ---- item out -------------------------------------------------------------------------------


async def open_issue(
    db: AsyncSession, ticket: Ticket, ingredient_id: uuid.UUID
) -> TicketStockIssue | None:
    return (
        await db.execute(
            select(TicketStockIssue)
            .where(
                TicketStockIssue.ticket_id == ticket.id,
                TicketStockIssue.ingredient_id == ingredient_id,
                TicketStockIssue.resolved_at.is_(None),
            )
            .order_by(TicketStockIssue.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()


async def mark_out(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    ingredient_id: uuid.UUID,
    actor: Actor,
    *,
    now: datetime | None = None,
) -> Ladder:
    """Item out (Phase 5 behaviour + pantry level + issue + ladder)."""
    now = now or utcnow()
    ingredient = await ticket_svc.check_item_out(db, ticket, ingredient_id, actor)
    if ingredient_id in await stock_svc.staple_ids(db):
        # The pantry is the single source of truth (F-5.6-04); stock_issue goes out below.
        await stock_svc.set_level(
            db, household, ingredient_id, StockLevel.out, by=actor.user_id, now=now
        )
    issue = await open_issue(db, ticket, ingredient_id)
    if issue is None:
        issue = TicketStockIssue(
            ticket_id=ticket.id,
            ingredient_id=ingredient_id,
            step=LadderStep.save_dish,
            raised_by=actor.user_id,
            created_at=now,
        )
        db.add(issue)
        await db.flush()
    ctx = await ticket_context(db, household, ticket)
    ladder = await compute(db, household, ctx, ingredient, issue, now=now)
    issue.step = ladder.step
    await ticket_svc.mark_item_out(
        db,
        household,
        ticket,
        ingredient_id,
        actor,
        now,
        detail={
            "issue_id": str(issue.id),
            "step": str(ladder.step),
            "swaps": len(ladder.swaps),
            "alternatives": len(ladder.alternatives),
        },
    )
    await db.flush()
    return ladder


async def ladder_for(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    issue: TicketStockIssue,
    *,
    now: datetime | None = None,
) -> Ladder:
    ingredient = await db.get(Ingredient, issue.ingredient_id)
    if ingredient is None:
        raise NotFound("ingredient_not_found")
    ctx = await ticket_context(db, household, ticket)
    return await compute(db, household, ctx, ingredient, issue, now=now)


# ---- resolve ---------------------------------------------------------------------------------


def _perm(kind: ApprovalType) -> Action:
    return Action.approve_dish_change if kind == ApprovalType.change_dish else Action.approve_swap


async def _pending(db: AsyncSession, issue: TicketStockIssue) -> Approval | None:
    if issue.approval_id is None:
        return None
    approval = await db.get(Approval, issue.approval_id)
    return approval if approval is not None and approval.decision is None else None


def _invalid_option(code: str, **details: Any) -> AppError:
    return AppError(
        code,
        "That option is not available for this item.",
        "Ye vikalp is saaman ke liye nahi hai.",
        status_code=422,
        details=details,
    )


async def _find_issue(
    db: AsyncSession, ticket: Ticket, ingredient_id: uuid.UUID | None
) -> TicketStockIssue:
    stmt = select(TicketStockIssue).where(
        TicketStockIssue.ticket_id == ticket.id, TicketStockIssue.resolved_at.is_(None)
    )
    if ingredient_id is not None:
        stmt = stmt.where(TicketStockIssue.ingredient_id == ingredient_id)
    issue = (
        await db.execute(stmt.order_by(TicketStockIssue.created_at.desc()).limit(1))
    ).scalar_one_or_none()
    if issue is None:
        raise Conflict(
            "no_stock_issue",
            "No open stock issue on this ticket.",
            "Is ticket par koi saaman ki dikkat khuli nahi hai.",
        )
    return issue


async def resolve(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    actor: Actor,
    *,
    action: str,
    substitute_ingredient_id: uuid.UUID | None = None,
    recipe_id: uuid.UUID | None = None,
    ingredient_id: uuid.UUID | None = None,
    now: datetime | None = None,
) -> Approval | None:
    """POST /tickets/{id}/stock-issue/resolve. Returns the Approval (None for a plain skip)."""
    now = now or utcnow()
    cook = await ticket_svc.ticket_cook(db, ticket)
    if not (ticket_svc.acts_as_assignee(actor, cook) or actor.is_admin or actor.is_member):
        raise Forbidden(details={"action": "resolve_stock_issue"})
    if ticket.status not in ticket_svc.OPEN_STATUSES:
        raise ticket_svc._closed_error()
    issue = await _find_issue(db, ticket, ingredient_id)
    if await _pending(db, issue) is not None:
        raise Conflict(
            "approval_pending",
            "Waiting for the family to answer.",
            "Ghar walon ke jawab ka intezaar hai.",
            details={"approval_id": str(issue.approval_id)},
        )
    ladder = await ladder_for(db, household, ticket, issue, now=now)
    payload: dict[str, Any] = {
        "issue_id": str(issue.id),
        "action": action,
        "ingredient_id": str(ladder.ingredient.id),
        "ingredient_name": ladder.ingredient.name_en,
        "replaces_recipe_id": str(ladder.replaces_recipe_id) if ladder.replaces_recipe_id else None,
    }
    if action == "skip":
        if not ladder.skip["ok"]:
            raise _invalid_option("skip_not_allowed", ingredient_id=str(ladder.ingredient.id))
        await apply(db, household, ticket, issue, payload, by=actor.user_id, approval=None, now=now)
        return None
    if action == "swap":
        chosen = next(
            (s for s in ladder.swaps if s["substitute_ingredient_id"] == substitute_ingredient_id),
            None,
        )
        if chosen is None:
            raise _invalid_option(
                "invalid_substitute", substitute_ingredient_id=str(substitute_ingredient_id)
            )
        payload |= {
            "substitute_ingredient_id": str(chosen["substitute_ingredient_id"]),
            "substitute_name": chosen["name"],
            "ratio": chosen["ratio"],
            "note_hi": chosen["note_hi"],
            "fit_after": chosen["fit_after"],
        }
        kind = ApprovalType.swap
    elif action == "change_dish":
        chosen = next((a for a in ladder.alternatives if a["id"] == str(recipe_id)), None)
        if chosen is None or ladder.replaces_recipe_id is None:
            raise _invalid_option("invalid_recipe", recipe_id=str(recipe_id))
        payload |= {"recipe_id": str(recipe_id), "recipe_name": chosen["name"]}
        kind = ApprovalType.change_dish
    else:
        raise _invalid_option("invalid_action", action=action)

    outcome = resolve_approval(actor, _perm(kind), Resource(requested_by_user_id=actor.user_id))
    approval = Approval(
        household_id=household.id,
        ticket_id=ticket.id,
        type=kind,
        requested_by=actor.user_id,
        decided_by=actor.user_id if outcome.self_approved else None,
        decision=ApprovalDecision.approved if outcome.self_approved else None,
        decided_at=now if outcome.self_approved else None,
        auto=outcome.self_approved,
        expires_at=None if outcome.self_approved else now + APPROVAL_TTL,
        payload=payload,
        created_at=now,
    )
    db.add(approval)
    await db.flush()
    issue.approval_id = approval.id
    what = _what(payload)
    ticket_svc.log_event(
        db,
        ticket,
        "approval_requested",
        actor.user_id,
        {
            **_event_detail(payload),
            "type": str(kind),
            "approval_id": str(approval.id),
            "self_approved": approval.auto,
            "expires_at": approval.expires_at.isoformat() if approval.expires_at else None,
            "text": what,
        },
        now,
    )
    if approval.auto:
        await apply(
            db, household, ticket, issue, payload, by=actor.user_id, approval=approval, now=now
        )
        if actor.is_family_cook and not actor.is_admin:
            # §2.1: a family cook approves her own change; the admin is told.
            await notify.emit(
                db,
                "stock_issue_resolved",
                household,
                ticket=ticket,
                assignee=cook,
                actor_user_id=actor.user_id,
                params=ticket_svc.ticket_params(
                    household, ticket, cook, what=what, item=ladder.ingredient.name_en
                ),
                now=now,
            )
    else:
        bump_ticket(ticket)
        await notify.emit(
            db,
            "approval_request",
            household,
            ticket=ticket,
            assignee=cook,
            actor_user_id=actor.user_id,
            params=ticket_svc.ticket_params(household, ticket, cook, what=what),
            data={"approval_id": approval.id},
            now=now,
        )
    return approval


def bump_ticket(ticket: Ticket) -> None:
    ticket_svc.bump(ticket)


def _what(payload: dict[str, Any]) -> str:
    """Approval ``detail`` line, e.g. "Curd → Milk"."""
    item = payload.get("ingredient_name") or "Saaman"
    if payload.get("action") == "swap":
        return f"{item} → {payload.get('substitute_name')}"
    if payload.get("action") == "change_dish":
        return f"Dish → {payload.get('recipe_name')} ({item} khatam)"
    if payload.get("items"):
        return "Ration: " + ", ".join(str(i) for i in payload["items"])[:160]
    return f"{item} ke bina"


def _event_detail(payload: dict[str, Any]) -> dict[str, Any]:
    keep = (
        "issue_id",
        "action",
        "ingredient_id",
        "ingredient_name",
        "substitute_ingredient_id",
        "substitute_name",
        "ratio",
        "recipe_id",
        "recipe_name",
        "replaces_recipe_id",
    )
    return {k: payload[k] for k in keep if payload.get(k) is not None}


# ---- apply --------------------------------------------------------------------------------------


async def apply(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    issue: TicketStockIssue,
    payload: dict[str, Any],
    *,
    by: uuid.UUID | None,
    approval: Approval | None,
    now: datetime,
) -> None:
    """Rewrite the ticket snapshot for an approved (or approval-free) ladder action."""
    action = payload["action"]
    ingredient_id = uuid.UUID(payload["ingredient_id"])
    dishes = [dict(d) for d in ticket.dishes or []]
    if action in ("skip", "swap"):
        ids = menu_svc.parse_uuid_list(d.get("recipe_id") for d in dishes)
        recipes = await menu_svc.load_recipes(db, ids)
        to_id = payload.get("substitute_ingredient_id") if action == "swap" else None
        entry = {
            "from_ingredient_id": str(ingredient_id),
            "from_name": payload.get("ingredient_name"),
            "to_ingredient_id": to_id,
            "to_name": payload.get("substitute_name") if action == "swap" else None,
            "ratio": payload.get("ratio") if action == "swap" else 0,
            "note_hi": payload.get("note_hi"),
        }
        for d in dishes:
            recipe = recipes.get(uuid.UUID(str(d["recipe_id"])))
            if recipe is None or not _uses(recipe, ingredient_id):
                continue
            d["swaps"] = [
                s for s in d.get("swaps") or [] if s.get("from_ingredient_id") != str(ingredient_id)
            ] + [entry]
            if (
                action == "swap"
                and payload.get("fit_after")
                and str(recipe.id) == payload.get("replaces_recipe_id")
            ):
                d["summary"] = payload["fit_after"]
        issue.resolution = IssueResolution.swap if action == "swap" else IssueResolution.skip
        issue.substitute_ingredient_id = uuid.UUID(to_id) if to_id else None
        event = "stock_swap" if action == "swap" else "stock_skip"
    else:
        new_id = uuid.UUID(payload["recipe_id"])
        old_id = payload["replaces_recipe_id"]
        plan = await menu_svc.plan_for(
            db,
            household,
            [new_id],
            [e["member_id"] for e in ticket.eaters or []],
            ticket.guests or {},
        )
        if not plan.dishes:
            raise NotFound("recipe_not_found")
        replaced = False
        for i, d in enumerate(dishes):
            if str(d.get("recipe_id")) == old_id:
                dishes[i] = plan.dishes[0]
                replaced = True
                break
        if not replaced:
            dishes.append(plan.dishes[0])
        issue.resolution = IssueResolution.change_dish
        issue.new_recipe_id = new_id
        event = "stock_change_dish"
    ticket.dishes = dishes
    issue.resolved_at = now
    await db.flush()
    remaining = (
        await db.execute(
            select(TicketStockIssue.id).where(
                TicketStockIssue.ticket_id == ticket.id, TicketStockIssue.resolved_at.is_(None)
            )
        )
    ).first()
    ticket.stock_issue_open = remaining is not None
    ticket_svc.bump(ticket)
    detail = _event_detail(payload)
    if approval is not None:
        detail |= {"approval_id": str(approval.id), "auto": approval.auto}
    # One microsecond later than the approval events of the same call, so the change log
    # (ordered by time) always reads "approval ... -> change".
    ticket_svc.log_event(db, ticket, event, by, detail, now + timedelta(microseconds=1))
    if action == "change_dish" and ticket.menu_id is not None:
        await ticket_svc._sync_menu(db, ticket)


# ---- decide ----------------------------------------------------------------------------------


async def get_approval(db: AsyncSession, household: Household, approval_id: uuid.UUID) -> Approval:
    approval = await db.get(Approval, approval_id)
    if approval is None or approval.household_id != household.id:
        raise NotFound()
    return approval


def is_expired(approval: Approval, now: datetime) -> bool:
    return (
        approval.decision is None and approval.expires_at is not None and approval.expires_at <= now
    )


async def decide(
    db: AsyncSession,
    household: Household,
    approval: Approval,
    actor: Actor,
    decision: str,
    *,
    now: datetime | None = None,
) -> Approval:
    """POST /approvals/{id}/decide. First response wins (guarded UPDATE)."""
    now = now or utcnow()
    if approval.type == ApprovalType.ration:
        from app.services import ration as ration_svc

        if approval.ration_request_id is None:
            raise NotFound()
        req = await ration_svc.get_request(db, household, approval.ration_request_id)
        await ration_svc.decide(db, household, req, actor, decision, now=now)
        await db.refresh(approval)
        return approval
    res = Resource(requested_by_user_id=approval.requested_by)
    if not resolve_approval(actor, _perm(approval.type), res).allowed:
        raise Forbidden(details={"action": _perm(approval.type).value})
    if is_expired(approval, now):
        raise Conflict(
            "approval_expired",
            "This request timed out.",
            "Is request ka samay nikal gaya.",
        )
    target = ApprovalDecision.approved if decision == "approved" else ApprovalDecision.rejected
    result = await db.execute(
        update(Approval)
        .where(Approval.id == approval.id, Approval.decision.is_(None))
        .values(decision=target, decided_by=actor.user_id, decided_at=now)
        .execution_options(synchronize_session=False)
    )
    await db.refresh(approval)
    if result.rowcount != 1:  # type: ignore[attr-defined]
        raise Conflict(
            "already_decided",
            "Somebody already answered.",
            "Kisi ne pehle hi jawab de diya.",
            details={"decision": str(approval.decision) if approval.decision else None},
        )
    ticket = await db.get(Ticket, approval.ticket_id) if approval.ticket_id else None
    if ticket is None:
        return approval
    issue = await db.get(TicketStockIssue, uuid.UUID(approval.payload["issue_id"]))
    what = _what(approval.payload)
    ticket_svc.log_event(
        db,
        ticket,
        "approval_approved" if target == ApprovalDecision.approved else "approval_rejected",
        actor.user_id,
        {
            **_event_detail(approval.payload),
            "type": str(approval.type),
            "approval_id": str(approval.id),
            "text": what,
        },
        now,
    )
    if target == ApprovalDecision.approved and issue is not None and issue.resolved_at is None:
        await apply(
            db,
            household,
            ticket,
            issue,
            dict(approval.payload),
            by=actor.user_id,
            approval=approval,
            now=now,
        )
    else:
        ticket_svc.bump(ticket)
    cook = await ticket_svc.ticket_cook(db, ticket)
    await notify.emit(
        db,
        "approval_decided",
        household,
        ticket=ticket,
        actor_user_id=actor.user_id,
        requester=approval.requested_by,
        params=ticket_svc.ticket_params(
            household,
            ticket,
            cook,
            what=what,
            decision="haan" if target == ApprovalDecision.approved else "nahi",
        ),
        data={"approval_id": approval.id},
        now=now,
    )
    return approval


# ---- expiry (worker) ----------------------------------------------------------------------


async def expire_approvals(db: AsyncSession, now: datetime) -> list[uuid.UUID]:
    """Pending swap / dish-change approvals past ``expires_at`` -> expired + admin alert."""
    rows = list(
        (
            await db.execute(
                select(Approval).where(
                    Approval.decision.is_(None),
                    Approval.type.in_(list(TICKET_APPROVALS)),
                    Approval.expires_at.is_not(None),
                    Approval.expires_at <= now,
                )
            )
        ).scalars()
    )
    done: list[uuid.UUID] = []
    for approval in rows:
        result = await db.execute(
            update(Approval)
            .where(Approval.id == approval.id, Approval.decision.is_(None))
            .values(decision=ApprovalDecision.expired, decided_at=now)
            .execution_options(synchronize_session=False)
        )
        if result.rowcount != 1:  # type: ignore[attr-defined]
            continue
        household = await db.get(Household, approval.household_id)
        ticket = await db.get(Ticket, approval.ticket_id) if approval.ticket_id else None
        if household is None or household.deleted_at is not None or ticket is None:
            continue
        ticket.stock_issue_open = True
        ticket_svc.bump(ticket)
        ticket_svc.log_event(
            db,
            ticket,
            "stock_issue_timeout",
            None,
            {
                **_event_detail(approval.payload),
                "type": str(approval.type),
                "approval_id": str(approval.id),
            },
            now,
        )
        cook = await ticket_svc.ticket_cook(db, ticket)
        await notify.emit(
            db,
            "stock_issue_timeout",
            household,
            ticket=ticket,
            params=ticket_svc.ticket_params(
                household, ticket, cook, item=approval.payload.get("ingredient_name") or "Saaman"
            ),
            data={"approval_id": approval.id},
            now=now,
        )
        done.append(approval.id)
    await db.flush()
    return done


# ---- read helpers -----------------------------------------------------------------------------


def approval_view(
    a: Approval, now: datetime | None = None, names: dict[uuid.UUID, str] | None = None
) -> dict[str, Any]:
    now = now or utcnow()
    names = names or {}
    status = (
        str(a.decision)
        if a.decision is not None
        else "expired"
        if is_expired(a, now)
        else "pending"
    )
    return {
        "id": a.id,
        "ticket_id": a.ticket_id,
        "ration_request_id": a.ration_request_id,
        "type": str(a.type),
        "status": status,
        "requested_by": ref(a.requested_by, names),
        "decided_by": ref(a.decided_by, names),
        "decision": str(a.decision) if a.decision is not None else None,
        "detail": _what(dict(a.payload or {})),
        "decided_at": a.decided_at,
        "auto": a.auto,
        "expires_at": a.expires_at,
        "payload": dict(a.payload or {}),
        "created_at": a.created_at,
    }


async def list_approvals(
    db: AsyncSession,
    household: Household,
    *,
    status: str | None = None,
    requested_by: uuid.UUID | None = None,
    now: datetime | None = None,
) -> list[Approval]:
    now = now or utcnow()
    stmt = select(Approval).where(Approval.household_id == household.id)
    if status == "pending":
        stmt = stmt.where(Approval.decision.is_(None)).where(
            (Approval.expires_at.is_(None)) | (Approval.expires_at > now)
        )
    elif status in ("approved", "rejected", "expired"):
        stmt = stmt.where(Approval.decision == ApprovalDecision(status))
    if requested_by is not None:
        stmt = stmt.where(Approval.requested_by == requested_by)
    return list((await db.execute(stmt.order_by(Approval.created_at.desc()))).scalars())
