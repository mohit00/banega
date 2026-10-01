"""Kitchen admin (Phase 5): menus, tickets (change log inline), cooks' duty log, inbox items,
and a "Ticket board" page: one day's tickets grouped by status.

Tickets are read-only here: status changes go through the API so the state table
(app.services.tickets.STATE_TABLE), the change log and notifications stay consistent.
"""

from __future__ import annotations

import html
from datetime import date, datetime
from typing import Any, ClassVar
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.requests import Request
from starlette.responses import HTMLResponse, Response
from starlette_admin import JSONField, StringField
from starlette_admin.contrib.sqla import Admin, InlineModelView, ModelView
from starlette_admin.routing import route
from starlette_admin.views import CustomView

from app.models import (
    Cook,
    CookDutyLog,
    Household,
    InboxItem,
    Menu,
    Ticket,
    TicketEvent,
    TicketStatus,
)
from app.services.labels import slot_label, time_label


def _session(request: Request) -> AsyncSession:
    session = request.state.session
    assert isinstance(session, AsyncSession)
    return session


class _ReadOnly(ModelView):
    def can_create(self, request: Request) -> bool:
        return False

    def can_edit(self, request: Request) -> bool:
        return False


class MenuView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "date",
        "slot",
        JSONField("eaters"),
        JSONField("guests"),
        "servings",
        "due_at",
        "assignee_cook_id",
        StringField("notes"),
        "ticket_id",
        "version",
        "updated_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = ["eaters", "guests", "notes"]
    searchable_fields: ClassVar[list[Any]] = ["slot"]
    sortable_fields: ClassVar[list[Any]] = ["date", "due_at", "updated_at"]


class TicketEventInline(InlineModelView):
    model = TicketEvent
    label = "Change log"
    extra = 0
    fields: ClassVar[list[Any]] = ["at", "by_user_id", StringField("action"), JSONField("detail")]

    def can_create(self, request: Request) -> bool:
        return False

    def can_edit(self, request: Request) -> bool:
        return False

    def can_delete(self, request: Request) -> bool:
        return False


class TicketView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "date",
        "slot",
        "status",
        "due_at",
        "assignee_cook_id",
        "confirmed_by_user_id",
        JSONField("dishes"),
        JSONField("eaters"),
        JSONField("guests"),
        "servings",
        StringField("notes"),
        "stock_issue_open",
        "updated",
        "accepted_at",
        "started_at",
        "completed_at",
        "cancel_reason",
        "status_changed_at",
        "no_show_alerted_at",
        "version",
        "created_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = [
        "dishes",
        "eaters",
        "guests",
        "notes",
        "confirmed_by_user_id",
        "accepted_at",
        "started_at",
        "cancel_reason",
        "status_changed_at",
        "no_show_alerted_at",
    ]
    searchable_fields: ClassVar[list[Any]] = ["status", "slot", "date"]
    sortable_fields: ClassVar[list[Any]] = ["date", "due_at", "status", "created_at"]
    inlines: ClassVar[list[Any]] = [TicketEventInline]


class CookDutyLogView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "cook_id",
        "at",
        "on_duty",
        "until",
        "reason",
        "by_user_id",
    ]
    sortable_fields: ClassVar[list[Any]] = ["at"]


class InboxItemView(_ReadOnly):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "user_id",
        StringField("event"),
        StringField("title"),
        StringField("body"),
        "ticket_id",
        "read_at",
        "created_at",
    ]
    searchable_fields: ClassVar[list[Any]] = ["event", "title"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "event"]


# ---- ticket board -----------------------------------------------------------------------------

_BOARD_CSS = """
body{margin:0;font-family:Figtree,"Helvetica Neue",Arial,sans-serif;background:#F4F5EF;color:#1B1B18}
header{padding:16px 24px;display:flex;gap:14px;align-items:center;flex-wrap:wrap}
header a{color:#0E7C3A;font-weight:700;text-decoration:none}
form{display:flex;gap:8px;align-items:center}
.cols{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px;padding:0 24px 24px}
.col h2{font-size:14px;text-transform:uppercase;letter-spacing:.04em;margin:0 0 8px}
.card{background:#fff;border:1px solid #E6E6DF;border-radius:12px;padding:10px 12px;margin-bottom:10px;font-size:13px}
.card b{display:block;font-size:14px}
.muted{color:#6A6A62}.flag{color:#8B2A17;font-weight:700}
.empty{color:#9A9A92;font-size:12px}
"""  # noqa: E501

BOARD_ORDER: tuple[TicketStatus, ...] = (
    TicketStatus.unassigned,
    TicketStatus.new,
    TicketStatus.accepted,
    TicketStatus.cooking,
    TicketStatus.ready,
    TicketStatus.not_confirmed,
    TicketStatus.completed,
    TicketStatus.cancelled,
)


def render_board(
    day: date,
    tickets: list[Ticket],
    households: dict[Any, Household],
    cooks: dict[Any, Cook],
    back: str,
) -> str:
    e = html.escape
    cols = []
    for st in BOARD_ORDER:
        cards = []
        for t in (t for t in tickets if t.status == st):
            h = households.get(t.household_id)
            cook = cooks.get(t.assignee_cook_id) if t.assignee_cook_id else None
            dishes = ", ".join(str(d.get("name", "")) for d in t.dishes or [])
            flags = []
            if t.stock_issue_open:
                flags.append("stock issue")
            if t.updated:
                flags.append("updated")
            due = time_label(t.due_at, h.timezone if h else "")
            cards.append(
                "<div class='card'>"
                f"<b>{e(slot_label(t.slot))} &middot; {e(due)}</b>"
                f"<div>{e(h.name if h else '?')}</div>"
                f"<div class='muted'>{e(dishes) or '-'}</div>"
                f"<div class='muted'>Cook: {e(cook.name or '') if cook else '<i>none</i>'}"
                f" &middot; {float(t.servings or 0):g} servings</div>"
                + (f"<div class='flag'>{e(', '.join(flags))}</div>" if flags else "")
                + f"<div class='muted'><a href='ticket/detail?pk={t.id}'>open</a>"
                f" &middot; v{t.version}</div></div>"
            )
        body = "".join(cards) or "<div class='empty'>-</div>"
        cols.append(f"<div class='col'><h2>{e(str(st))} ({len(cards)})</h2>{body}</div>")
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>Ticket board</title><style>{_BOARD_CSS}</style></head><body>"
        f"<header><a href='{e(back)}'>&larr; Admin</a><strong>Ticket board</strong>"
        f"<form method='get'><input type='date' name='date' value='{day.isoformat()}'>"
        "<button type='submit'>Show</button></form>"
        f"<span class='muted'>{len(tickets)} ticket(s)</span></header>"
        f"<div class='cols'>{''.join(cols)}</div></body></html>"
    )


class TicketBoardView(CustomView):
    """Today's tickets (IST) across households, one column per status. ``?date=YYYY-MM-DD``."""

    menu_label = "Ticket board"
    icon = "fa fa-table-columns"
    path = "/ticket-board"
    route_name = "ticket-board"

    @route("")
    async def index(self, request: Request) -> Response:
        raw = request.query_params.get("date")
        try:
            day = date.fromisoformat(raw) if raw else datetime.now(ZoneInfo("Asia/Kolkata")).date()
        except ValueError:
            day = datetime.now(ZoneInfo("Asia/Kolkata")).date()
        db = _session(request)
        tickets = list(
            (
                await db.execute(select(Ticket).where(Ticket.date == day).order_by(Ticket.due_at))
            ).scalars()
        )
        hh_ids = {t.household_id for t in tickets}
        cook_ids = {t.assignee_cook_id for t in tickets if t.assignee_cook_id}
        households = (
            {
                h.id: h
                for h in (
                    await db.execute(select(Household).where(Household.id.in_(hh_ids)))
                ).scalars()
            }
            if hh_ids
            else {}
        )
        cooks = (
            {
                c.id: c
                for c in (await db.execute(select(Cook).where(Cook.id.in_(cook_ids)))).scalars()
            }
            if cook_ids
            else {}
        )
        back = str(request.url_for("admin:index"))
        return HTMLResponse(render_board(day, tickets, households, cooks, back))


def register_kitchen_views(admin: Admin) -> None:
    admin.add_view(MenuView(Menu, icon="fa fa-utensils"))
    admin.add_view(TicketView(Ticket, icon="fa fa-receipt"))
    admin.add_view(CookDutyLogView(CookDutyLog, icon="fa fa-calendar-check"))
    admin.add_view(InboxItemView(InboxItem, icon="fa fa-inbox"))
    admin.add_view(TicketBoardView())
