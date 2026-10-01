"""Catalogue import: ingredients, staples, recipes, app config and the demo household.

Every loader is idempotent (upsert by slug / key / phone / name) so ``python -m app.cli seed``
can run on every deploy. Recipe ingredient lines are free text ("Mota poha 2 cup",
"Adrak-lahsun"); :class:`AliasMatcher` maps each line to one or more catalogue ingredients by
longest alias match, keeping the original text as ``display_text``.
"""

from __future__ import annotations

import os
import re
import uuid
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import timedelta
from decimal import Decimal, InvalidOperation
from fractions import Fraction
from pathlib import Path
from typing import Any, Literal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import utcnow
from app.models import (
    AppConfig,
    Cook,
    CookKind,
    CookLoginMode,
    Diet,
    DishCategory,
    Household,
    HouseholdMembership,
    Ingredient,
    IngredientCategory,
    Member,
    MembershipStatus,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
    ScalingRule,
    Spice,
    Staple,
    StockLevel,
    Subscription,
    SubscriptionStatus,
    SubstitutionRule,
    User,
)
from app.models.catalogue import DEFAULT_INGREDIENT_FLAGS
from app.services import allergens as allergen_svc
from app.services.tagging import apply_derived

# Repo checkout: <repo>/content. In containers the dev compose mounts it at /srv/content;
# elsewhere set CONTENT_DIR or pass --content-dir.
CONTENT_DIR = Path(os.environ.get("CONTENT_DIR") or Path(__file__).resolve().parents[3] / "content")
DEV_ADMIN_PHONE = "+919999999999"

PublishMode = Literal["none", "clean", "all"]

_TOKEN_RE = re.compile(r"[a-z]+")
_QTY_RE = re.compile(
    r"(?P<num>\d+(?:\.\d+)?(?:/\d+)?)\s*(?P<unit>cups?|kg|gm?|ml|l|tsp|tbsp|gaddi|pc)?\b",
    re.IGNORECASE,
)
_MAX_NGRAM = 4
_OPTIONAL_RE = re.compile(r"\((?:optional|vaikalpik|agar ho)\)", re.IGNORECASE)

# Content-team spellings for dish categories -> DishCategory.
_CATEGORY_ALIASES = {
    "dry_sabzi": "sabzi",
    "gravy_sabzi": "sabzi",
    "bread": "roti_paratha",
    "roti": "roti_paratha",
    "paratha": "roti_paratha",
    "gravy": "curry",
    "chutney": "side",
    "pickle": "side",
    "achaar": "side",
    "raita": "salad_raita",
    "salad": "salad_raita",
    "dessert": "sweet",
    "mithai": "sweet",
    "nashta": "breakfast",
}


def _dish_category(value: str | None) -> DishCategory | None:
    key = (value or "other").strip().lower().replace("-", "_").replace(" ", "_")
    key = _CATEGORY_ALIASES.get(key, key)
    try:
        return DishCategory(key)
    except ValueError:
        return None


# prototype diet value -> editorial_diet
_DIET_MAP = {"veg": "veg", "egg": "egg", "nonveg": "non_veg", "non_veg": "non_veg"}
# prototype diet label -> Diet
_MEMBER_DIET = {
    "veg": Diet.veg,
    "jain": Diet.jain,
    "egg": Diet.eggetarian,
    "eggetarian": Diet.eggetarian,
    "non-veg": Diet.non_veg,
    "non_veg": Diet.non_veg,
    "no_onion_garlic": Diet.no_onion_garlic,
    "pescatarian": Diet.pescatarian,
}


def load_json(name: str, content_dir: Path | None = None) -> Any:
    import json

    return json.loads(((content_dir or CONTENT_DIR) / name).read_text(encoding="utf-8"))


# ---- alias matching ---------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class LineMatch:
    text: str
    slugs: tuple[str, ...]
    qty: Decimal | None = None
    unit: str | None = None


def _tokens(text: str) -> list[str]:
    return _TOKEN_RE.findall(text.lower())


class AliasMatcher:
    """Greedy longest-n-gram match of ingredient aliases inside a free-text line."""

    def __init__(self, ingredients: Iterable[tuple[str, str, Sequence[str]]]) -> None:
        """``ingredients``: (slug, name_en, aliases)."""
        self._map: dict[tuple[str, ...], str] = {}
        for slug, name_en, aliases in ingredients:
            for phrase in (*aliases, name_en, slug.replace("-", " ")):
                key = tuple(_tokens(phrase))
                if key and key not in self._map:
                    self._map[key] = slug

    def match(self, text: str) -> list[str]:
        toks = _tokens(text)
        out: list[str] = []
        i = 0
        while i < len(toks):
            for n in range(min(_MAX_NGRAM, len(toks) - i), 0, -1):
                slug = self._map.get(tuple(toks[i : i + n]))
                if slug is not None:
                    if slug not in out:
                        out.append(slug)
                    i += n
                    break
            else:
                i += 1
        return out

    def parse_line(self, text: str) -> LineMatch:
        slugs = tuple(self.match(text))
        qty: Decimal | None = None
        unit: str | None = None
        m = _QTY_RE.search(text)
        # A quantity only belongs to the line when the line is a single ingredient.
        if m and len(slugs) == 1:
            try:
                qty = Decimal(str(float(Fraction(m.group("num")))))
            except (ValueError, ZeroDivisionError, InvalidOperation):
                qty = None
            raw_unit = (m.group("unit") or "pc").lower()
            unit = {"cups": "cup", "gm": "g"}.get(raw_unit, raw_unit)
        return LineMatch(text=text, slugs=slugs, qty=qty, unit=unit if qty is not None else None)


# ---- reports ----------------------------------------------------------------------------


@dataclass
class ImportReport:
    created: int = 0
    updated: int = 0
    unmatched: dict[str, list[str]] = field(default_factory=dict)
    violations: dict[str, list[dict[str, Any]]] = field(default_factory=dict)
    published: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def summary(self) -> str:
        parts = [f"created={self.created}", f"updated={self.updated}"]
        if self.published:
            parts.append(f"published={len(self.published)}")
        if self.unmatched:
            parts.append(f"unmatched_lines={sum(len(v) for v in self.unmatched.values())}")
        if self.violations:
            parts.append(f"with_violations={len(self.violations)}")
        if self.errors:
            parts.append(f"errors={len(self.errors)}")
        return " ".join(parts)


# ---- ingredients + staples --------------------------------------------------------------


def _flags(raw: Mapping[str, Any] | None) -> dict[str, Any]:
    flags = dict(DEFAULT_INGREDIENT_FLAGS)
    for key, value in (raw or {}).items():
        if key in flags:
            flags[key] = value
    return flags


async def load_ingredients(db: AsyncSession, rows: Sequence[Mapping[str, Any]]) -> ImportReport:
    report = ImportReport()
    existing = {i.slug: i for i in (await db.execute(select(Ingredient))).scalars()}
    for row in rows:
        slug = str(row["slug"]).strip()
        ing = existing.get(slug)
        if ing is None:
            ing = Ingredient(slug=slug)
            db.add(ing)
            existing[slug] = ing
            report.created += 1
        else:
            report.updated += 1
        ing.name_en = row["name_en"]
        ing.name_hi = row.get("name_hi")
        ing.aliases = list(row.get("aliases") or [])
        ing.category = IngredientCategory(row.get("category") or "other")
        try:
            ing.allergens = allergen_svc.strict(row.get("allergens"))
        except ValueError as exc:
            raise ValueError(f"ingredient {slug}: {exc}") from exc
        ing.flags = _flags(row.get("flags"))
        ing.scaling_rule = ScalingRule(row.get("scaling_rule") or "linear")
        ing.trackable = bool(row.get("trackable", False))
        ing.purchase_unit = row.get("purchase_unit")
        pack = row.get("pack_size")
        ing.pack_size = Decimal(str(pack)) if pack is not None else None
        ing.perishable = bool(row.get("perishable", False))
        ing.is_active = bool(row.get("is_active", True))
    await db.flush()

    # Staples = the trackable subset, in seed order.
    staples = {s.ingredient_id: s for s in (await db.execute(select(Staple))).unique().scalars()}
    for order, row in enumerate(r for r in rows if r.get("trackable")):
        ing = existing[str(row["slug"]).strip()]
        staple = staples.get(ing.id)
        if staple is None:
            staple = Staple(ingredient_id=ing.id)
            db.add(staple)
        staple.sort_order = order
        staple.default_pack_qty = ing.pack_size
        staple.low_threshold = (
            (ing.pack_size * Decimal("0.2")).quantize(Decimal("0.001")) if ing.pack_size else None
        )
    await db.flush()
    return report


async def build_matcher(db: AsyncSession) -> tuple[AliasMatcher, dict[str, Ingredient]]:
    ings = list((await db.execute(select(Ingredient).where(Ingredient.is_active))).scalars())
    by_slug = {i.slug: i for i in ings}
    return AliasMatcher((i.slug, i.name_en, i.aliases or []) for i in ings), by_slug


# ---- recipes ----------------------------------------------------------------------------


async def load_recipes(
    db: AsyncSession, rows: Sequence[Mapping[str, Any]], *, publish: PublishMode = "clean"
) -> ImportReport:
    """Upsert recipes by slug and rebuild their ingredient rows from ``ingredients_text``.

    ``publish``: "none" keeps the seed status; "clean" publishes recipes without policy
    violations; "all" publishes everything (dev demo only; violations stay recorded).
    """
    report = ImportReport()
    matcher, by_slug = await build_matcher(db)
    existing = {r.slug: r for r in (await db.execute(select(Recipe))).scalars()}
    for row in rows:
        slug = str(row.get("slug") or row["id"]).strip()
        recipe = existing.get(slug)
        if recipe is None:
            recipe = Recipe(slug=slug, version=1)
            db.add(recipe)
            existing[slug] = recipe
            report.created += 1
        else:
            recipe.version = (recipe.version or 1) + 1
            report.updated += 1
        recipe.name = row["name"]
        recipe.name_hi = row.get("name_hi")
        recipe.sub = row.get("sub")
        category = _dish_category(row.get("dish_category"))
        if category is None:
            report.errors.append(
                f"{row['slug']}: unknown dish_category {row.get('dish_category')!r}"
            )
            category = DishCategory.other
        recipe.dish_category = category
        recipe.cuisine = row.get("cuisine")
        recipe.meal_slots = list(row.get("meal_slots") or [])
        recipe.mins = int(row.get("mins") or 30)
        recipe.spice = int(row.get("spice") or 2)
        recipe.tags = list(row.get("tags") or [])
        recipe.colour = row.get("colour")
        recipe.image_url = row.get("image_url")
        recipe.video_url = row.get("video_url")
        recipe.base_servings = int(row.get("base_servings") or 4)
        recipe.steps_en = list(row.get("steps_en") or [])
        recipe.steps_hi = list(row.get("steps_hi") or [])
        recipe.vrat_ok = bool(row.get("vrat_ok", False))
        recipe.editorial_jain_safe = bool(
            row.get("jain_safe_editorial", row.get("editorial_jain_safe", False))
        )
        diet = row.get("diet") or row.get("editorial_diet")
        recipe.editorial_diet = _DIET_MAP.get(str(diet)) if diet else None
        await db.flush()
        await db.refresh(recipe, attribute_names=["ingredients"])

        ingredients: list[Ingredient] = []
        unmatched: list[str] = []
        new_rows: list[RecipeIngredient] = []
        for order, line in enumerate(row.get("ingredients_text") or []):
            # "Dhaniya (optional)" marks an ingredient the cook may skip; the
            # marker is dropped before matching but kept in the display text.
            is_optional = bool(_OPTIONAL_RE.search(line))
            m = matcher.parse_line(_OPTIONAL_RE.sub(" ", line).strip())
            if not m.slugs:
                unmatched.append(line)
                continue
            for slug_ in m.slugs:
                ing = by_slug[slug_]
                ingredients.append(ing)
                new_rows.append(
                    RecipeIngredient(
                        ingredient_id=ing.id,
                        ingredient=ing,
                        qty=m.qty,
                        unit=m.unit,
                        display_text=line,
                        is_main=order == 0 and not is_optional,
                        optional=is_optional,
                        sort_order=order,
                    )
                )
        # Replacing the collection deletes the old rows (delete-orphan cascade).
        recipe.ingredients = new_rows
        if unmatched:
            report.unmatched[slug] = unmatched

        apply_derived(recipe, ingredients)
        if unmatched:
            recipe.policy_violations = [
                *recipe.policy_violations,
                {
                    "code": "unmatched_ingredients",
                    "lines": unmatched,
                    "message": "Some ingredient lines did not match the catalogue.",
                },
            ]
        if recipe.policy_violations:
            report.violations[slug] = recipe.policy_violations

        wanted = RecipeStatus(row.get("status") or "draft")
        if publish == "all" or (publish == "clean" and not recipe.policy_violations):
            wanted = RecipeStatus.published
        elif wanted == RecipeStatus.published and recipe.policy_violations:
            # Never publish through an import when the policy check fails.
            wanted = RecipeStatus.reviewed
            report.errors.append(f"{slug}: not published, policy violations")
        if wanted == RecipeStatus.published and recipe.status != RecipeStatus.published:
            recipe.published_at = utcnow()
        recipe.status = wanted
        if wanted == RecipeStatus.published:
            report.published.append(slug)
    await db.flush()
    return report


# ---- substitutions (F-5.9-01: swaps come only from curated rules) --------------------------


async def load_substitutions(db: AsyncSession, rows: Sequence[Mapping[str, Any]]) -> ImportReport:
    """Upsert by (from, to, cuisine_scope). ``ratio: 0`` with ``to == from`` is the
    "can be left out" rule the out-of-stock ladder offers as a skip."""
    report = ImportReport()
    by_slug = {i.slug: i for i in (await db.execute(select(Ingredient))).scalars()}
    existing = {
        (r.from_ingredient_id, r.to_ingredient_id, r.cuisine_scope): r
        for r in (await db.execute(select(SubstitutionRule))).scalars()
    }
    for row in rows:
        src, dst = by_slug.get(str(row["from"])), by_slug.get(str(row["to"]))
        if src is None or dst is None:
            report.errors.append(f"{row['from']} -> {row['to']}: unknown ingredient")
            continue
        scope = row.get("cuisine_scope")
        rule = existing.get((src.id, dst.id, scope))
        if rule is None:
            rule = SubstitutionRule(
                from_ingredient_id=src.id, to_ingredient_id=dst.id, cuisine_scope=scope
            )
            db.add(rule)
            existing[(src.id, dst.id, scope)] = rule
            report.created += 1
        else:
            report.updated += 1
        rule.ratio = Decimal(str(row.get("ratio", 1)))
        rule.note_hi = row.get("note_hi")
        rule.note_en = row.get("note_en")
        rule.is_active = bool(row.get("is_active", True))
    await db.flush()
    return report


# ---- app config -------------------------------------------------------------------------


async def load_app_config(db: AsyncSession, data: Mapping[str, Any]) -> ImportReport:
    report = ImportReport()
    for key, value in data.items():
        row = await db.get(AppConfig, key)
        if row is None:
            db.add(AppConfig(key=key, value=value))
            report.created += 1
        else:
            row.value = value
            report.updated += 1
    await db.flush()
    return report


# ---- demo household ---------------------------------------------------------------------


async def load_demo_household(
    db: AsyncSession, data: Mapping[str, Any], *, admin_phone: str = DEV_ADMIN_PHONE
) -> ImportReport:
    """Create (or refresh) the demo household with a dev admin login and its members."""
    report = ImportReport()
    user = (await db.execute(select(User).where(User.phone == admin_phone))).scalar_one_or_none()
    if user is None:
        user = User(phone=admin_phone, name="Demo admin")
        db.add(user)
        await db.flush()
    hh_data = data["household"]
    membership = (
        await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.user_id == user.id,
                HouseholdMembership.status == MembershipStatus.active,
            )
        )
    ).scalar_one_or_none()
    household = await db.get(Household, membership.household_id) if membership else None
    if household is None:
        household = Household(name=hh_data["name"])
        db.add(household)
        await db.flush()
        report.created += 1
    else:
        report.updated += 1
    household.name = hh_data["name"]
    household.timezone = hh_data.get("timezone", "Asia/Kolkata")
    household.default_servings = int(hh_data.get("default_servings", 4))
    household.deleted_at = None

    existing = {
        m.name: m
        for m in (
            await db.execute(select(Member).where(Member.household_id == household.id))
        ).scalars()
    }
    first_member_id: uuid.UUID | None = None
    for m in data.get("members", []):
        member = existing.get(m["name"])
        if member is None:
            member = Member(household_id=household.id, name=m["name"])
            db.add(member)
        member.colour = m.get("colour")
        member.diet = _MEMBER_DIET.get(str(m.get("diet", "veg")).lower(), Diet.veg)
        member.spice = Spice(str(m.get("spice", "medium")).lower())
        member.needs = list(m.get("needs") or [])
        member.cuisines = list(m.get("cuisines") or [])
        known, other = allergen_svc.split(m.get("allergens"))
        member.allergens = known
        member.allergens_other = ", ".join(other) or m.get("allergens_other")
        member.dislikes = list(m.get("dislikes") or [])
        member.nonveg_exclusions = list(m.get("nonveg_exclusions") or [])
        member.no_dairy = bool(m.get("no_dairy", False))
        member.is_kid = bool(m.get("is_kid", False))
        member.archived_at = None
        await db.flush()
        if first_member_id is None:
            first_member_id = member.id

    if membership is None:
        membership = HouseholdMembership(
            user_id=user.id,
            household_id=household.id,
            is_admin=True,
            is_member=True,
            member_id=first_member_id,
            status=MembershipStatus.active,
        )
        db.add(membership)
    await load_demo_cooks(db, household, data.get("cooks") or DEMO_COOKS)
    await load_demo_stock(db, household, data.get("stock") or {})
    sub = (
        await db.execute(select(Subscription).where(Subscription.household_id == household.id))
    ).scalar_one_or_none()
    if sub is None:
        db.add(
            Subscription(
                household_id=household.id,
                status=SubscriptionStatus.trial,
                trial_ends_at=utcnow() + timedelta(days=get_settings().TRIAL_DAYS),
            )
        )
    elif sub.status == SubscriptionStatus.trial:
        # Re-seeding keeps the demo usable: the trial restarts from today.
        sub.trial_ends_at = utcnow() + timedelta(days=get_settings().TRIAL_DAYS)
    await db.flush()
    return report


DEMO_COOK_PHONE = "+919999999990"
# Phase 5 demo cooks: a hired primary cook (logs in by OTP on DEMO_COOK_PHONE and sees cook
# mode) and Mummy as the family backup cook (profile-only, so the admin runs her tickets).
DEMO_COOKS: list[dict[str, Any]] = [
    {"kind": "hired", "name": "Ramesh ji", "phone": DEMO_COOK_PHONE, "is_primary": True},
    {"kind": "family", "member": "Mummy", "is_backup": True},
]


async def load_demo_cooks(
    db: AsyncSession, household: Household, cooks: Sequence[Mapping[str, Any]]
) -> None:
    """Idempotent: matched by phone (hired) or member name (family)."""
    existing = list(
        (await db.execute(select(Cook).where(Cook.household_id == household.id))).scalars()
    )
    members = {
        m.name: m
        for m in (
            await db.execute(select(Member).where(Member.household_id == household.id))
        ).scalars()
    }
    for spec in cooks:
        kind = CookKind(spec["kind"])
        cook: Cook | None
        if kind == CookKind.hired:
            cook = next((c for c in existing if c.phone == spec["phone"]), None)
            if cook is None:
                cook = Cook(household_id=household.id, kind=kind, phone=spec["phone"])
                db.add(cook)
            cook.name = spec.get("name") or "Cook"
            cook.login_mode = CookLoginMode.own
        else:
            member = members.get(spec["member"])
            if member is None:
                continue
            cook = next((c for c in existing if c.member_id == member.id), None)
            if cook is None:
                cook = Cook(household_id=household.id, kind=kind, member_id=member.id)
                db.add(cook)
            cook.name = member.name
            cook.login_mode = CookLoginMode.via_admin
        cook.is_primary = bool(spec.get("is_primary"))
        cook.is_backup = bool(spec.get("is_backup"))
        cook.on_duty = True
        cook.off_duty_until = None
        cook.removed_at = None
    await db.flush()


async def load_demo_stock(
    db: AsyncSession, household: Household, levels: Mapping[str, str]
) -> None:
    """Every staple ``in``, then the demo overrides (dahi out, paneer low, ...)."""
    from app.services import stock as stock_svc

    await stock_svc.list_stock(db, household)
    by_slug = {
        i.slug: i.id
        for i in (
            await db.execute(select(Ingredient).where(Ingredient.slug.in_(list(levels))))
        ).scalars()
    }
    rows = await stock_svc.household_rows(db, household.id)
    for row in rows.values():
        row.level = StockLevel.in_
    for slug, level in levels.items():
        iid = by_slug.get(slug)
        if iid is not None and iid in rows:
            rows[iid].level = StockLevel(level)
    await db.flush()


# ---- everything -------------------------------------------------------------------------


@dataclass
class SeedReport:
    ingredients: ImportReport
    recipes: ImportReport
    config: ImportReport
    household: ImportReport | None
    substitutions: ImportReport = field(default_factory=ImportReport)


async def seed_all(
    db: AsyncSession,
    *,
    content_dir: Path | None = None,
    publish: PublishMode = "clean",
    with_demo_household: bool = True,
    admin_phone: str = DEV_ADMIN_PHONE,
) -> SeedReport:
    ing = await load_ingredients(db, load_json("ingredients.seed.json", content_dir))
    rec = await load_recipes(db, load_json("recipes.seed.json", content_dir), publish=publish)
    subs_path = (content_dir or CONTENT_DIR) / "substitutions.seed.json"
    subs = (
        await load_substitutions(db, load_json("substitutions.seed.json", content_dir))
        if subs_path.exists()
        else ImportReport()
    )
    cfg = await load_app_config(db, load_json("app-config.seed.json", content_dir))
    hh = None
    if with_demo_household:
        hh = await load_demo_household(
            db, load_json("demo-household.seed.json", content_dir), admin_phone=admin_phone
        )
    await db.commit()
    return SeedReport(ingredients=ing, recipes=rec, config=cfg, household=hh, substitutions=subs)


async def retire_same_name(db: AsyncSession, keep_slugs: Iterable[str]) -> list[str]:
    """Move other published recipes that share a name with ``keep_slugs`` back to draft.

    Used when a master sheet supersedes older copies of the same dish (e.g. the demo seed's
    ``khichdi`` vs the sheet's ``moong-dal-khichdi``). Nothing is deleted.
    """
    keep = set(keep_slugs)
    recipes = list((await db.execute(select(Recipe))).scalars())
    names = {r.name.strip().lower() for r in recipes if r.slug in keep}
    retired = []
    for r in recipes:
        if (
            r.slug not in keep
            and r.status == RecipeStatus.published
            and r.name.strip().lower() in names
        ):
            r.status = RecipeStatus.draft
            retired.append(r.slug)
    return sorted(retired)
