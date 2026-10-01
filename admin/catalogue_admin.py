"""Catalogue admin (Phase 2): ingredients, staples, recipes (+ ingredient rows), substitutions,
app config (+ the Maharaj golden query set download), the tile "Card preview" and CSV
import/export.

Derived diet flags are read-only here: they are recomputed from the ingredients whenever a
recipe, one of its ingredient rows, or an ingredient's flags change (F-5.2-01a, F-6-06).
Publishing is a row/batch action that refuses while ``policy_violations`` is non-empty.
"""

from __future__ import annotations

import html
import os
import uuid
from pathlib import Path
from typing import Any, ClassVar

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.datastructures import UploadFile
from starlette.requests import Request
from starlette.responses import HTMLResponse, RedirectResponse, Response
from starlette_admin import (
    BooleanField,
    DecimalField,
    FileField,
    IntegerField,
    JSONField,
    StringField,
    TagsField,
    URLField,
    action,
    link_row_action,
    row_action,
)
from starlette_admin.contrib.sqla import Admin, InlineModelView, ModelView
from starlette_admin.exceptions import ActionFailed, FormValidationError
from starlette_admin.flash import flash
from starlette_admin.routing import route
from starlette_admin.security.csrf import csrf_input
from starlette_admin.views import CustomView

from app.models import (
    AppConfig,
    Ingredient,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
    Staple,
    SubstitutionRule,
)
from app.services import allergens as allergen_svc
from app.services import csv_io, publishing
from app.services.catalogue import diet_mark
from security import SoftDeleteView

MEDIA_DIR = Path(os.environ.get("MEDIA_DIR", "media")).resolve()
MEDIA_URL = os.environ.get("MEDIA_URL", "/media").rstrip("/")
MAX_IMAGE_BYTES = 5 * 1024 * 1024
_IMAGE_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}

RO: list[Any] = ["id", "created_at", "updated_at"]


def _session(request: Request) -> AsyncSession:
    session = request.state.session
    assert isinstance(session, AsyncSession)
    return session


async def save_image(upload: UploadFile, prefix: str) -> str:
    """Store an uploaded photo under MEDIA_DIR/recipes and return its public URL.

    TODO(phase-2b): S3 + CDN and WebP variants (build plan §1.6).
    """
    ext = _IMAGE_TYPES.get(upload.content_type or "")
    if ext is None:
        raise FormValidationError({"image_upload": "Only JPEG, PNG or WebP images are allowed."})
    data = await upload.read()
    if len(data) > MAX_IMAGE_BYTES:
        raise FormValidationError({"image_upload": "Image is larger than 5 MB."})
    name = f"{prefix}-{uuid.uuid4().hex[:10]}.{ext}"
    folder = MEDIA_DIR / "recipes"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_bytes(data)
    return f"{MEDIA_URL}/recipes/{name}"


# ---- ingredients, staples -----------------------------------------------------------------


class IngredientView(SoftDeleteView):
    """Delete deactivates (is_active=False): recipe_ingredients reference ingredients with
    ON DELETE RESTRICT, and history must keep resolving."""

    fields: ClassVar[list[Any]] = [
        "id",
        StringField("slug", required=True),
        StringField("name_en", label="Name (EN)", required=True),
        StringField("name_hi", label="Name (HI)"),
        TagsField("aliases", label="Aliases (Hinglish spellings)"),
        "category",
        TagsField("allergens", label="Allergens (peanut, tree_nut, milk, gluten, ...)"),
        JSONField(
            "flags",
            label="Flags {root_veg, onion_garlic, meat_type, egg, dairy, gluten, honey, "
            "mushroom, fermented}",
        ),
        "scaling_rule",
        "trackable",
        "purchase_unit",
        DecimalField("pack_size"),
        "perishable",
        "is_active",
        "updated_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = ["flags", "aliases", "updated_at"]
    searchable_fields: ClassVar[list[Any]] = ["slug", "name_en", "name_hi"]
    sortable_fields: ClassVar[list[Any]] = ["slug", "name_en", "category", "updated_at"]
    exclude_fields_from_create: ClassVar[list[Any]] = RO
    exclude_fields_from_edit: ClassVar[list[Any]] = RO
    # CSV import runs through the catalogue importer (see "Catalogue CSV"); export stays.
    importers: ClassVar[list[Any]] = []

    async def validate(self, request: Request, data: dict[str, Any]) -> None:
        # F-5.2-03: picklist values only, synonyms normalised ("Peanuts" -> peanut).
        try:
            data["allergens"] = allergen_svc.strict(data.get("allergens"))
        except ValueError as exc:
            raise FormValidationError({"allergens": str(exc)}) from exc
        await super().validate(request, data)

    async def after_edit(self, request: Request, obj: Any) -> None:
        pulled = await publishing.recompute_for_ingredient(_session(request), obj.id)
        if pulled:
            flash(
                request,
                "Moved back to Reviewed (now violate the diet policy): " + ", ".join(pulled),
                "warning",
            )


class StapleView(ModelView):
    fields: ClassVar[list[Any]] = [
        "id",
        "ingredient",
        DecimalField("low_threshold"),
        DecimalField("default_pack_qty"),
        IntegerField("sort_order"),
    ]
    sortable_fields: ClassVar[list[Any]] = ["sort_order"]
    exclude_fields_from_create: ClassVar[list[Any]] = ["id"]
    exclude_fields_from_edit: ClassVar[list[Any]] = ["id"]
    importers: ClassVar[list[Any]] = []


# ---- recipes -------------------------------------------------------------------------------

_DERIVED = [
    "is_veg",
    "has_egg",
    "has_nonveg",
    "meat_types",
    "jain_safe",
    "no_onion_garlic",
    "has_root_veg",
    "dairy_free",
    "gluten_free",
    "allergens",
    "policy_violations",
]


class RecipeIngredientInline(InlineModelView):
    """Ingredient rows edited inside the recipe form. Every saved, edited or deleted row
    re-derives the recipe's diet flags and policy check."""

    model = RecipeIngredient
    label = "Ingredients"
    extra = 3
    fields: ClassVar[list[Any]] = [
        "id",
        "ingredient",
        StringField("display_text", label="Text as written (e.g. 'Mota poha 2 cup')"),
        DecimalField("qty"),
        StringField("unit"),
        BooleanField("is_main"),
        BooleanField("optional", label="Optional / garnish"),
        IntegerField("sort_order"),
    ]
    exclude_fields_from_create: ClassVar[list[Any]] = ["id"]
    exclude_fields_from_edit: ClassVar[list[Any]] = ["id"]

    async def after_create(self, request: Request, obj: Any) -> None:
        await publishing.recompute(_session(request), [obj.recipe_id])

    async def after_edit(self, request: Request, obj: Any) -> None:
        await publishing.recompute(_session(request), [obj.recipe_id])

    async def after_delete(self, request: Request, obj: Any) -> None:
        await publishing.recompute(_session(request), [obj.recipe_id])


def _violation_count(_: Request, obj: Any) -> int:
    return len(obj.policy_violations or [])


class RecipeView(ModelView):
    fields: ClassVar[list[Any]] = [
        "id",
        StringField("slug", required=True),
        StringField("name", required=True),
        StringField("name_hi", label="Name (HI)"),
        StringField("sub", label="Subtitle"),
        "status",
        "dish_category",
        "dish_group_id",
        StringField("cuisine"),
        TagsField("meal_slots", label="Slots (nashta, lunch, dinner, tiffin, shaam)"),
        IntegerField("mins"),
        IntegerField("spice", label="Spice (1-3)"),
        TagsField("tags", label="Editorial tags (lowOil, lowSugar, protein, kid, maida, ...)"),
        StringField("colour", label="Tile colour (#hex)"),
        URLField("image_url", label="Image URL"),
        FileField(
            "image_upload",
            label="Upload photo (JPEG/PNG/WebP, max 5 MB)",
            accept="image/jpeg,image/png,image/webp",
            max_size=MAX_IMAGE_BYTES,
            getter=lambda _r, _o: None,
            exclude_from_list=True,
            exclude_from_detail=True,
        ),
        URLField("video_url"),
        IntegerField("base_servings"),
        TagsField("steps_en", label="Steps (EN)"),
        TagsField("steps_hi", label="Steps (HI)"),
        BooleanField("vrat_ok"),
        StringField("editorial_diet", label="Editor says diet (veg / egg / non_veg)"),
        BooleanField("editorial_jain_safe", label="Editor says Jain-safe"),
        # ---- derived (read-only) ----
        BooleanField("is_veg", read_only=True),
        BooleanField("has_egg", read_only=True),
        BooleanField("has_nonveg", read_only=True),
        TagsField("meat_types", read_only=True),
        BooleanField("jain_safe", label="Jain-safe (derived)", read_only=True),
        BooleanField("no_onion_garlic", read_only=True),
        BooleanField("has_root_veg", read_only=True),
        BooleanField("dairy_free", read_only=True),
        BooleanField("gluten_free", read_only=True),
        TagsField("allergens", label="Allergens (derived)", read_only=True),
        IntegerField(
            "violation_count", label="Violations", getter=_violation_count, read_only=True
        ),
        JSONField("policy_violations", read_only=True),
        IntegerField("version", read_only=True),
        "published_at",
        "updated_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = [
        "id",
        "name_hi",
        "sub",
        "dish_group_id",
        "meal_slots",
        "tags",
        "colour",
        "image_url",
        "video_url",
        "base_servings",
        "steps_en",
        "steps_hi",
        "vrat_ok",
        "editorial_diet",
        "editorial_jain_safe",
        "meat_types",
        "has_root_veg",
        "dairy_free",
        "gluten_free",
        "allergens",
        "policy_violations",
        "published_at",
        "updated_at",
    ]
    exclude_fields_from_create: ClassVar[list[Any]] = [
        *RO,
        *_DERIVED,
        "violation_count",
        "status",
        "version",
        "published_at",
    ]
    exclude_fields_from_edit: ClassVar[list[Any]] = exclude_fields_from_create
    searchable_fields: ClassVar[list[Any]] = ["slug", "name", "cuisine"]
    sortable_fields: ClassVar[list[Any]] = ["name", "status", "mins", "updated_at"]
    importers: ClassVar[list[Any]] = []
    actions: ClassVar[list[str]] = ["mark_reviewed", "publish", "unpublish", "delete"]
    inlines: ClassVar[list[Any]] = [RecipeIngredientInline]

    # -- image upload: keep the file out of the ORM, store it, set image_url --
    async def _handle_upload(self, request: Request, data: dict[str, Any], obj: Any) -> None:
        value = data.get("image_upload")
        upload = value[0] if isinstance(value, tuple) else None
        if isinstance(upload, UploadFile) and upload.filename:
            obj.image_url = await save_image(upload, obj.slug or "recipe")
        if hasattr(obj, "image_upload"):
            del obj.image_upload

    async def before_create(self, request: Request, data: dict[str, Any], obj: Any) -> None:
        await self._handle_upload(request, data, obj)

    async def before_edit(self, request: Request, data: dict[str, Any], obj: Any) -> None:
        await self._handle_upload(request, data, obj)

    async def after_create(self, request: Request, obj: Any) -> None:
        await publishing.recompute(_session(request), [obj.id])

    async def after_edit(self, request: Request, obj: Any) -> None:
        await publishing.recompute(_session(request), [obj.id])

    # -- workflow actions --
    async def _recipes(self, request: Request, selection: Any) -> list[Recipe]:
        pks = selection if isinstance(selection, list) else await selection.pks()
        return await publishing.load_recipes(_session(request), [uuid.UUID(str(p)) for p in pks])

    @action(name="mark_reviewed", text="Mark reviewed", confirmation="Mark as Reviewed?")
    async def mark_reviewed_action(self, request: Request, selection: Any) -> str:
        recipes = await self._recipes(request, selection)
        try:
            for r in recipes:
                publishing.mark_reviewed(r)
        except publishing.PublishError as exc:
            raise ActionFailed(str(exc)) from exc
        await _session(request).flush()
        return f"{len(recipes)} recipe(s) marked Reviewed."

    @action(
        name="publish",
        text="Publish",
        confirmation="Publish the selected recipes? Recipes with policy violations are refused.",
    )
    async def publish_action(self, request: Request, selection: Any) -> str:
        recipes = await self._recipes(request, selection)
        errors = []
        for r in recipes:
            try:
                publishing.publish(r)
            except publishing.PublishError as exc:
                errors.append(str(exc))
        if errors:
            raise ActionFailed("Not published: " + "; ".join(errors))
        await _session(request).flush()
        return f"{len(recipes)} recipe(s) published."

    @action(name="unpublish", text="Unpublish (back to draft)", confirmation="Unpublish?")
    async def unpublish_action(self, request: Request, selection: Any) -> str:
        recipes = await self._recipes(request, selection)
        for r in recipes:
            publishing.unpublish(r)
        await _session(request).flush()
        return f"{len(recipes)} recipe(s) moved to Draft."

    @row_action(name="publish_row", text="Publish", confirmation="Publish this recipe?")
    async def publish_row_action(self, request: Request, pk: Any) -> str:
        return await self.publish_action(request, [pk])

    @link_row_action(name="card_preview", text="Card preview")
    def card_preview_row_action(self, request: Request, pk: Any) -> str:
        return str(request.url_for("admin:card-preview")) + f"?id={pk}"


class SubstitutionRuleView(ModelView):
    label = "Substitutions"
    fields: ClassVar[list[Any]] = [
        "id",
        "from_ingredient",
        "to_ingredient",
        DecimalField("ratio"),
        StringField("note_en"),
        StringField("note_hi"),
        StringField("cuisine_scope"),
        "is_active",
    ]
    exclude_fields_from_create: ClassVar[list[Any]] = ["id"]
    exclude_fields_from_edit: ClassVar[list[Any]] = ["id"]


class AppConfigView(ModelView):
    label = "App config"
    pk_attr = "key"
    fields: ClassVar[list[Any]] = [
        StringField("key", required=True),
        JSONField("value", required=True),
        "updated_at",
    ]
    exclude_fields_from_create: ClassVar[list[Any]] = ["updated_at"]
    exclude_fields_from_edit: ClassVar[list[Any]] = ["updated_at"]
    importers: ClassVar[list[Any]] = []


# ---- card preview ---------------------------------------------------------------------------

_TILE_CSS = """
body{margin:0;font-family:Figtree,"Helvetica Neue",Arial,sans-serif;background:#F4F5EF;color:#1B1B18}
header{padding:16px 24px;display:flex;gap:16px;align-items:center}
header a{color:#0E7C3A;font-weight:700;text-decoration:none}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(172px,1fr));gap:14px;padding:0 24px 24px}
.tile{background:#fff;border-radius:16px;border:1px solid #E6E6DF;overflow:hidden;display:flex;flex-direction:column}
.tile.focus{outline:3px solid #0E7C3A}
.ph{height:124px;position:relative;overflow:hidden}
.ph img{width:100%;height:100%;object-fit:cover;display:block}
.vm{position:absolute;left:8px;top:8px;width:14px;height:14px;border:1.5px solid #0E7C3A;border-radius:3px;display:flex;align-items:center;justify-content:center;background:#fff}
.vm i{width:7px;height:7px;border-radius:50%;background:#0E7C3A;display:block}
.vm.nv{border-color:#8B2A17}.vm.nv i{width:0;height:0;border-radius:0;background:none;border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:7px solid #8B2A17}
.vm.eg{border-color:#B86A00}.vm.eg i{background:#B86A00}
.mins{position:absolute;right:8px;top:8px;height:22px;padding:0 8px;border-radius:6px;font-size:11px;font-weight:800;background:#fff;color:#3A3A34;display:flex;align-items:center}
.body{padding:10px 10px 0;display:flex;flex-direction:column;gap:4px}
.name{font-size:14px;font-weight:800;line-height:1.2;min-height:34px}
.cuisine{font-size:11.5px;color:#55544E;font-weight:600}
.meta{padding:8px 10px 10px;font-size:11px;display:flex;flex-wrap:wrap;gap:4px}
.pill{padding:2px 6px;border-radius:6px;background:#EEF0E8;font-weight:700}
.pill.bad{background:#FCE6E2;color:#8B2A17}.pill.ok{background:#E7F4EA;color:#0A5E2C}
"""  # noqa: E501

_MARK_CLS = {"veg": "vm", "egg": "vm eg", "non_veg": "vm nv"}


def render_tile(r: Recipe, focus: bool = False) -> str:
    e = html.escape
    colour = e(r.colour or "#F7F3E6")
    img = f'<img src="{e(r.image_url)}" alt="{e(r.name)}">' if r.image_url else ""
    pills = [f'<span class="pill">{e(str(r.status))}</span>']
    if r.jain_safe:
        pills.append('<span class="pill ok">Jain-safe</span>')
    n = len(r.policy_violations or [])
    if n:
        pills.append(f'<span class="pill bad">{n} violation(s)</span>')
    return (
        f'<div class="tile{" focus" if focus else ""}" id="r-{r.id}">'
        f'<div class="ph" style="background:{colour}">{img}'
        f'<span class="{_MARK_CLS[diet_mark(r)]}"><i></i></span>'
        f'<span class="mins">{r.mins} MIN</span></div>'
        f'<div class="body"><div class="name">{e(r.name)}</div>'
        f'<div class="cuisine">{e(r.cuisine or "")}</div></div>'
        f'<div class="meta">{"".join(pills)}</div></div>'
    )


class CardPreviewView(CustomView):
    """The Home tile exactly as the app draws it: photo (or colour), diet mark, minutes, name,
    cuisine. ``?id=`` highlights one recipe; ``?status=`` filters."""

    menu_label = "Card preview"
    icon = "fa fa-table-cells"
    path = "/card-preview"
    route_name = "card-preview"

    @route("")
    async def index(self, request: Request) -> Response:
        stmt = select(Recipe).order_by(Recipe.name)
        status = request.query_params.get("status")
        if status in {s.value for s in RecipeStatus}:
            stmt = stmt.where(Recipe.status == status)
        rows = list((await _session(request).execute(stmt)).scalars())
        focus = request.query_params.get("id")
        tiles = "".join(render_tile(r, str(r.id) == focus) for r in rows)
        back = html.escape(str(request.url_for("admin:index")))
        page = (
            "<!doctype html><html><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>Card preview</title><style>{_TILE_CSS}</style></head><body>"
            f"<header><a href='{back}'>&larr; Admin</a><strong>Card preview</strong>"
            "<a href='?status=published'>Published</a><a href='?status=draft'>Draft</a>"
            "<a href='?status=reviewed'>Reviewed</a><a href='?'>All</a></header>"
            f"<div class='grid'>{tiles}</div>"
            + (
                f"<script>document.getElementById('r-{html.escape(focus)}')"
                "?.scrollIntoView({block:'center'})</script>"
                if focus
                else ""
            )
            + "</body></html>"
        )
        return HTMLResponse(page)


# ---- CSV import / export ---------------------------------------------------------------------


class CatalogueCsvView(CustomView):
    """CSV in the seed-file shape. Import upserts by slug and re-derives flags; a row asking
    for "published" with policy violations is stored as "reviewed"."""

    menu_label = "Catalogue CSV"
    icon = "fa fa-file-csv"
    path = "/catalogue-csv"
    route_name = "catalogue-csv"

    @route("")
    async def index(self, request: Request) -> Response:
        msg = html.escape(request.query_params.get("msg", ""))
        base = html.escape(str(request.url_for("admin:catalogue-csv")))
        return HTMLResponse(
            "<!doctype html><html><head><meta charset='utf-8'><title>Catalogue CSV</title>"
            "<style>body{font-family:Arial,sans-serif;margin:24px;max-width:720px}"
            "form{margin:16px 0;padding:12px;border:1px solid #ddd;border-radius:8px}</style>"
            f"</head><body><p><a href='{base}/../'>&larr; Admin</a></p><h2>Catalogue CSV</h2>"
            + (f"<pre>{msg}</pre>" if msg else "")
            + f"<p>Export: <a href='{base}/ingredients.csv'>ingredients.csv</a> · "
            f"<a href='{base}/recipes.csv'>recipes.csv</a></p>"
            + "".join(
                f"<form method='post' action='{base}/import/{kind}' enctype='multipart/form-data'>"
                f"{csrf_input(request)}"
                f"<b>Import {kind}</b> <input type='file' name='file' accept='.csv' required> "
                "<button type='submit'>Upload</button></form>"
                for kind in ("ingredients", "recipes")
            )
            + "<p>Lists use <code>|</code> between items. Recipe ingredient lines are matched "
            "to ingredients by alias; unmatched lines are reported as violations.</p>"
            "</body></html>"
        )

    @route("/ingredients.csv")
    async def export_ingredients(self, request: Request) -> Response:
        body = await csv_io.export_ingredients_csv(_session(request))
        return Response(
            body,
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=ingredients.csv"},
        )

    @route("/recipes.csv")
    async def export_recipes(self, request: Request) -> Response:
        body = await csv_io.export_recipes_csv(_session(request))
        return Response(
            body,
            media_type="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=recipes.csv"},
        )

    @route("/import/{kind}", methods=["POST"])
    async def import_csv(self, request: Request) -> Response:
        kind = request.path_params["kind"]
        form = await request.form()
        upload = form.get("file")
        if not isinstance(upload, UploadFile):
            return RedirectResponse("../?msg=No+file", status_code=303)
        text = (await upload.read()).decode("utf-8-sig")
        db = _session(request)
        if kind == "ingredients":
            report = await csv_io.import_ingredients_csv(db, text)
        elif kind == "recipes":
            report = await csv_io.import_recipes_csv(db, text)
        else:
            return RedirectResponse("../?msg=Unknown+kind", status_code=303)
        lines = [f"{kind}: {report.summary()}"]
        lines += [f"UNMATCHED {k}: {v}" for k, v in report.unmatched.items()]
        lines += [
            f"{k}: " + ", ".join(str(x.get("code")) for x in v)
            for k, v in report.violations.items()
        ]
        lines += report.errors
        from urllib.parse import quote

        base = str(request.url_for("admin:catalogue-csv"))
        return RedirectResponse(f"{base}?msg={quote(chr(10).join(lines))}", status_code=303)


# ---- Maharaj golden set (Phase 4) ------------------------------------------------------------


def golden_path() -> Path:
    from app.services.importer import CONTENT_DIR

    return Path(CONTENT_DIR) / "golden-queries.json"


def golden_report() -> tuple[dict[str, Any], list[tuple[str, dict[str, Any]]]]:
    """The golden set and the rule parser's misses on it (same comparison as the CI test)."""
    import json

    from app.services.maharaj.parse import RuleParser

    doc: dict[str, Any] = json.loads(golden_path().read_text(encoding="utf-8"))
    parser = RuleParser(doc.get("household_members") or [])
    misses: list[tuple[str, dict[str, Any]]] = []
    for item in doc.get("queries") or []:
        p = parser.parse(item["q"], doc.get("current_slot") or "lunch")
        e = item["expect"]
        got = {
            "slot": p.slot if p.explicit_slot else None,
            "tags": sorted(p.tags),
            "max_mins": p.max_mins,
            "cuisines": sorted(p.cuisines),
            "member_focus": p.member_focus,
        }
        exp = {
            "slot": e.get("slot"),
            "tags": sorted(e.get("tags") or []),
            "max_mins": e.get("max_mins"),
            "cuisines": sorted(e.get("cuisines") or []),
            "member_focus": e.get("member_focus"),
        }
        for key in ("ingredients_include", "ingredients_exclude"):
            if key in e:
                got[key], exp[key] = sorted(getattr(p, key)), sorted(e[key])
        for key in ("diet", "spice"):
            if key in e:
                got[key], exp[key] = getattr(p, key), e[key]
        diff = {k: {"got": got[k], "expected": exp[k]} for k in got if got[k] != exp[k]}
        if diff:
            misses.append((item["q"], diff))
    return doc, misses


class MaharajGoldenView(CustomView):
    """The chat parser's golden query set (content/golden-queries.json): stats, the rule
    parser's current accuracy and a download. Edit the file in the repo; CI requires >= 95%."""

    menu_label = "Maharaj golden set"
    icon = "fa fa-comments"
    path = "/maharaj-golden"
    route_name = "maharaj-golden"

    @route("")
    async def index(self, request: Request) -> Response:
        e = html.escape
        base = e(str(request.url_for("admin:maharaj-golden")))
        if not golden_path().exists():
            body = "<p>content/golden-queries.json is not available in this container.</p>"
        else:
            doc, misses = golden_report()
            queries = doc.get("queries") or []
            by_lang: dict[str, int] = {}
            for q in queries:
                by_lang[q.get("lang", "?")] = by_lang.get(q.get("lang", "?"), 0) + 1
            n = len(queries)
            acc = 100.0 * (n - len(misses)) / n if n else 0.0
            rows = "".join(
                f"<tr><td>{e(q)}</td><td><code>{e(str(d))}</code></td></tr>" for q, d in misses
            )
            body = (
                f"<p><b>{n}</b> queries ("
                + ", ".join(f"{e(k)}: {v}" for k, v in sorted(by_lang.items()))
                + f"). Rule parser accuracy: <b>{acc:.1f}%</b> (CI gate: 95%).</p>"
                f"<p><a href='{base}/golden-queries.json'>Download golden-queries.json</a></p>"
                + (f"<h3>Misses</h3><table border='1'>{rows}</table>" if rows else "")
            )
        return HTMLResponse(
            "<!doctype html><html><head><meta charset='utf-8'><title>Maharaj golden set</title>"
            "<style>body{font-family:Arial,sans-serif;margin:24px;max-width:900px}</style>"
            f"</head><body><p><a href='{base}/../'>&larr; Admin</a></p>"
            f"<h2>Maharaj golden set</h2>{body}</body></html>"
        )

    @route("/golden-queries.json")
    async def download(self, request: Request) -> Response:
        path = golden_path()
        if not path.exists():
            return Response("not found", status_code=404)
        return Response(
            path.read_bytes(),
            media_type="application/json; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=golden-queries.json"},
        )


def register_catalogue_views(admin: Admin) -> None:
    admin.add_view(IngredientView(Ingredient, icon="fa fa-carrot"))
    admin.add_view(StapleView(Staple, icon="fa fa-jar"))
    admin.add_view(RecipeView(Recipe, icon="fa fa-bowl-food"))
    admin.add_view(SubstitutionRuleView(SubstitutionRule, icon="fa fa-right-left"))
    admin.add_view(AppConfigView(AppConfig, icon="fa fa-sliders"))
    admin.add_view(MaharajGoldenView())
    admin.add_view(CardPreviewView())
    admin.add_view(CatalogueCsvView())


__all__ = ["register_catalogue_views", "render_tile", "save_image"]
