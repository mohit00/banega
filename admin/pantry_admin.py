"""Phase 6-7 admin: pantry stock, ration requests (items inline), approvals, ratings,
subscriptions (status filter), consents, and a "Kitchen health" page (pending approvals, low
and out stock per household, this week's ratings, subscriptions by status).

Everything is read-only here: stock, approvals and ratings change through the API so the
§2.1 rules, the ticket change log and notifications stay consistent.
"""

from __future__ import annotations

import html
from collections import Counter, defaultdict
from datetime import timedelta
from typing import Any, ClassVar

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.requests import Request
from starlette.responses import HTMLResponse, Response
from starlette_admin import JSONField, StringField
from starlette_admin.contrib.sqla import Admin, InlineModelView, ModelView
from starlette_admin.routing import route
from starlette_admin.views import CustomView

from app.core.security import utcnow
from app.models import (
    Approval,
    Consent,
    Household,
    Ingredient,
    Rating,
    RationItem,
    RationRequest,
    StockItem,
    StockLevel,
    Subscription,
    SubscriptionStatus,
)


def _session(request: Request) -> AsyncSession:
    session = request.state.session
    assert isinstance(session, AsyncSession)
    return session


class _ReadOnly(ModelView):
    def can_create(self, request: Request) -> bool:
        return False

    def can_edit(self, request: Request) -> bool:
        return False


class StockItemView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "ingredient_id",
        "level",
        "qty",
        StringField("unit"),
        "updated_by",
        "updated_at",
    ]
    sortable_fields: ClassVar[list[Any]] = ["updated_at", "level"]


class RationItemInline(InlineModelView):
    model = RationItem
    label = "Items"
    extra = 0
    fields: ClassVar[list[Any]] = [
        StringField("name"),
        "ingredient_id",
        "qty",
        StringField("unit"),
        StringField("note"),
    ]

    def can_create(self, request: Request) -> bool:
        return False

    def can_edit(self, request: Request) -> bool:
        return False

    def can_delete(self, request: Request) -> bool:
        return False


class RationRequestView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "ticket_id",
        "status",
        "auto_approved",
        "raised_by",
        "decided_by",
        "decided_at",
        StringField("note"),
        StringField("decision_note"),
        "bought_at",
        "created_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = ["note", "decision_note", "ticket_id"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "status"]
    inlines: ClassVar[list[Any]] = [RationItemInline]


class ApprovalView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "ticket_id",
        "ration_request_id",
        "type",
        "decision",
        "auto",
        "requested_by",
        "decided_by",
        "decided_at",
        "expires_at",
        JSONField("payload"),
        "created_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = ["payload", "ration_request_id"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "expires_at", "type"]


class RatingView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "ticket_id",
        "recipe_id",
        "member_id",
        "rated_by_user_id",
        "score",
        StringField("note"),
        "created_at",
    ]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "score"]


class ConsentView(_ReadOnly):
    fields: ClassVar[list[Any]] = ["id", "user_id", "household_id", "version", "accepted_at"]
    sortable_fields: ClassVar[list[Any]] = ["accepted_at", "version"]


class SubscriptionView(ModelView):
    """Search with a status (trial | active | grace | expired) to filter by it."""

    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "status",
        "product_id",
        "store",
        "trial_ends_at",
        "renews_at",
        "grace_until",
        "original_transaction_id",
        "purchase_token",
        "last_event_at",
        "trial_phone",
        "updated_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = [
        "original_transaction_id",
        "purchase_token",
        "trial_phone",
        "last_event_at",
    ]
    searchable_fields: ClassVar[list[Any]] = ["status", "product_id", "store"]
    sortable_fields: ClassVar[list[Any]] = ["updated_at", "trial_ends_at", "renews_at", "status"]

    def get_search_query(self, request: Request, term: str) -> Any:
        values = {s.value for s in SubscriptionStatus}
        if term.strip().lower() in values:
            return Subscription.status == SubscriptionStatus(term.strip().lower())
        like = f"%{term}%"
        return or_(Subscription.product_id.ilike(like), Subscription.store.ilike(like))


# ---- kitchen health -------------------------------------------------------------------------

_CSS = """
body{margin:0;font-family:Figtree,"Helvetica Neue",Arial,sans-serif;background:#F4F5EF;color:#1B1B18}
header{padding:16px 24px;display:flex;gap:14px;align-items:center}
header a{color:#0E7C3A;font-weight:700;text-decoration:none}
main{padding:0 24px 24px;display:grid;gap:16px;grid-template-columns:repeat(auto-fill,minmax(320px,1fr))}
section{background:#fff;border:1px solid #E6E6DF;border-radius:12px;padding:12px 16px}
h2{font-size:14px;text-transform:uppercase;letter-spacing:.04em;margin:0 0 8px}
table{border-collapse:collapse;width:100%;font-size:13px}
td,th{text-align:left;padding:4px 6px;border-bottom:1px solid #F0F0EA}
.big{font-size:28px;font-weight:800}.muted{color:#6A6A62}.warn{color:#8B2A17;font-weight:700}
"""  # noqa: E501


def render_health(data: dict[str, Any], back: str) -> str:
    e = html.escape
    names: dict[Any, str] = data["households"]

    def rows(items: list[tuple[str, ...]]) -> str:
        if not items:
            return "<tr><td class='muted'>-</td></tr>"
        return "".join("<tr>" + "".join(f"<td>{e(c)}</td>" for c in r) + "</tr>" for r in items)

    pending = [
        (
            names.get(a.household_id, "?"),
            str(a.type),
            str((a.payload or {}).get("ingredient_name") or ""),
            a.expires_at.strftime("%d %b %H:%M") if a.expires_at else "-",
        )
        for a in data["pending"]
    ]
    stock = [
        (names.get(hid, "?"), str(c["low"]), str(c["out"]), ", ".join(c["out_names"][:4]))
        for hid, c in data["stock"].items()
    ]
    ratings = [
        (names.get(hid, "?"), str(c["count"]), f"{c['avg']:.2f}")
        for hid, c in data["ratings"].items()
    ]
    subs = [(k, str(v)) for k, v in sorted(data["subs"].items())]
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>Kitchen health</title><style>{_CSS}</style></head><body>"
        f"<header><a href='{e(back)}'>&larr; Admin</a><strong>Kitchen health</strong>"
        f"<span class='muted'>last 7 days</span></header><main>"
        f"<section><h2>Pending approvals</h2><div class='big'>{len(pending)}</div>"
        "<table><tr><th>Household</th><th>Type</th><th>Item</th><th>Expires</th></tr>"
        f"{rows(pending)}</table></section>"
        "<section><h2>Low / out stock</h2>"
        f"<div class='big'>{data['low_total']} low &middot; "
        f"<span class='warn'>{data['out_total']} out</span></div>"
        "<table><tr><th>Household</th><th>Low</th><th>Out</th><th>Out items</th></tr>"
        f"{rows(stock)}</table></section>"
        f"<section><h2>Ratings this week</h2><div class='big'>{data['ratings_total']}</div>"
        "<table><tr><th>Household</th><th>Ratings</th><th>Avg (1-3)</th></tr>"
        f"{rows(ratings)}</table></section>"
        "<section><h2>Subscriptions</h2>"
        f"<table><tr><th>Status</th><th>Households</th></tr>{rows(subs)}</table></section>"
        "</main></body></html>"
    )


async def health_data(db: AsyncSession) -> dict[str, Any]:
    now = utcnow()
    pending = list(
        (
            await db.execute(
                select(Approval)
                .where(Approval.decision.is_(None))
                .where(or_(Approval.expires_at.is_(None), Approval.expires_at > now))
                .order_by(Approval.created_at.desc())
                .limit(50)
            )
        ).scalars()
    )
    stock: dict[Any, dict[str, Any]] = defaultdict(lambda: {"low": 0, "out": 0, "out_names": []})
    for hid, level, name in (
        await db.execute(
            select(StockItem.household_id, StockItem.level, Ingredient.name_en)
            .join(Ingredient, Ingredient.id == StockItem.ingredient_id)
            .where(StockItem.level.in_([StockLevel.low, StockLevel.out]))
        )
    ).all():
        entry = stock[hid]
        if level == StockLevel.out:
            entry["out"] += 1
            entry["out_names"].append(name)
        else:
            entry["low"] += 1
    ratings: dict[Any, dict[str, Any]] = {}
    for hid, count, avg in (
        await db.execute(
            select(Rating.household_id, func.count(Rating.id), func.avg(Rating.score))
            .where(Rating.created_at >= now - timedelta(days=7))
            .group_by(Rating.household_id)
        )
    ).all():
        ratings[hid] = {"count": int(count), "avg": float(avg or 0)}
    subs = Counter(str(s) for s in (await db.execute(select(Subscription.status))).scalars())
    ids = {a.household_id for a in pending} | set(stock) | set(ratings)
    households = (
        {
            h.id: h.name
            for h in (await db.execute(select(Household).where(Household.id.in_(ids)))).scalars()
        }
        if ids
        else {}
    )
    return {
        "pending": pending,
        "stock": dict(stock),
        "ratings": ratings,
        "subs": dict(subs),
        "households": households,
        "low_total": sum(c["low"] for c in stock.values()),
        "out_total": sum(c["out"] for c in stock.values()),
        "ratings_total": sum(c["count"] for c in ratings.values()),
    }


class KitchenHealthView(CustomView):
    menu_label = "Kitchen health"
    icon = "fa fa-heart-pulse"
    path = "/kitchen-health"
    route_name = "kitchen-health"

    @route("")
    async def index(self, request: Request) -> Response:
        data = await health_data(_session(request))
        return HTMLResponse(render_health(data, str(request.url_for("admin:index"))))


def register_pantry_views(admin: Admin) -> None:
    admin.add_view(StockItemView(StockItem, icon="fa fa-jar"))
    admin.add_view(RationRequestView(RationRequest, icon="fa fa-basket-shopping"))
    admin.add_view(ApprovalView(Approval, icon="fa fa-check-double"))
    admin.add_view(RatingView(Rating, icon="fa fa-star"))
    admin.add_view(ConsentView(Consent, icon="fa fa-file-signature"))
    admin.add_view(KitchenHealthView())


# Re-exported for main.py (the Subscription view lives here with its status filter).
__all__ = ["SubscriptionView", "register_pantry_views"]
