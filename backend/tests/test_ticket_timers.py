"""Worker timers with a fake clock: not_confirmed (due_at + 3 h), 24 h auto-close, no-show
(due_at - 90 min, still new), 20:00 tomorrow's tickets, off-duty auto-return."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

from httpx import AsyncClient

from app.core.db import get_sessionmaker
from app.models import Cook, Ticket
from app.services import ticket_timers
from tests.conftest import Login
from tests.kitchen_fixtures import IST, Kitchen, future_day, make_kitchen


async def _run(now: datetime) -> ticket_timers.SweepReport:
    async with get_sessionmaker()() as db:
        report = await ticket_timers.run_all(db, now)
        await db.commit()
    return report


def _due(t: dict[str, Any]) -> datetime:
    return datetime.fromisoformat(t["due_at"])


async def _events(k: Kitchen, headers: dict[str, str] | None = None) -> list[str]:
    r = await k.client.get("/v1/inbox", headers=headers or k.admin)
    return [i["event"] for i in r.json()]


async def test_not_confirmed_after_3h_then_cancelled_after_24h(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    papa = await k.add_family("Papa")
    t = await k.ticket(["gatte"], assignee_cook_id=papa["id"])  # self: accepted
    due = _due(t)
    assert (await _run(due + timedelta(hours=2, minutes=59))).not_confirmed == []
    report = await _run(due + timedelta(hours=3))
    assert report.not_confirmed == [uuid.UUID(t["id"])]
    after = await k.get(t)
    assert after["status"] == "not_confirmed"
    assert after["change_log"][-1]["by"]["name"] == "System"
    assert "not_confirmed_prompt" in await _events(k)
    # Running again is a no-op.
    assert (await _run(due + timedelta(hours=4))).not_confirmed == []
    # Admin may still answer within 24 h; here nobody does.
    assert (await _run(due + timedelta(hours=26))).auto_cancelled == []
    report = await _run(due + timedelta(hours=27, minutes=1))
    assert report.auto_cancelled == [uuid.UUID(t["id"])]
    closed = await k.get(t)
    assert closed["status"] == "cancelled" and closed["change_log"][-1]["action"] == "auto_closed"


async def test_admin_answers_khaana_bana(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    mummy = await k.add_family("Mummy")
    t = await k.ticket(["gatte"], assignee_cook_id=mummy["id"])
    await _run(_due(t) + timedelta(hours=3))
    r = await k.move(t, "completed")
    assert r.status_code == 200 and r.json()["status"] == "completed"


async def test_no_show_alert_once(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    t = await k.ticket(["gatte"])  # new, never accepted
    due = _due(t)
    assert (await _run(due - timedelta(minutes=91))).no_show == []
    report = await _run(due - timedelta(minutes=90))
    assert report.no_show == [uuid.UUID(t["id"])]
    assert (await _run(due - timedelta(minutes=60))).no_show == []
    assert (await _events(k)).count("no_show") == 1
    assert (await k.get(t))["change_log"][-1]["action"] == "no_show_alert"
    # Accepted tickets do not alert.
    cook_h = await k.cook_login()
    t2 = await k.ticket(["bhindi"], slot="dinner")
    await k.move(t2, "accepted", cook_h)
    assert (await _run(_due(t2) - timedelta(minutes=30))).no_show == []


async def test_tomorrow_tickets_at_20_local_once(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook_h = await k.cook_login()
    day = future_day(2)
    await k.ticket(["gatte"], day=day)
    await k.ticket(["bhindi"], day=day, slot="dinner")
    eve = datetime.combine(day - timedelta(days=1), datetime.min.time(), tzinfo=IST)
    assert (await _run(eve.replace(hour=19, minute=59))).tomorrow_notified == []
    report = await _run(eve.replace(hour=20, minute=0))
    assert len(report.tomorrow_notified) == 1
    assert (await _run(eve.replace(hour=20, minute=5))).tomorrow_notified == []
    inbox = (await client.get("/v1/inbox", headers=cook_h)).json()
    tomorrow = [i for i in inbox if i["event"] == "tomorrow_tickets"]
    assert len(tomorrow) == 1
    assert tomorrow[0]["title"] == "Kal ke 2 ticket"
    assert "Lunch 1:30 PM: Gatte ki Sabzi" in tomorrow[0]["body"]


async def test_off_duty_auto_return_moves_nothing_back(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook_h = await k.cook_login()
    mummy = await k.add_family("Mummy")
    await k.patch_cook("Mummy", is_backup=True)
    t = await k.ticket(["gatte"])
    until = _due(t) + timedelta(hours=1)
    await k.patch_cook("Ramesh ji", cook_h, on_duty=False, off_duty_until=until.isoformat())
    assert (await k.get(t))["assignee"]["cook_id"] == mummy["id"]
    assert (await _run(until - timedelta(minutes=1))).back_on_duty == []
    report = await _run(until)
    assert len(report.back_on_duty) == 1
    async with get_sessionmaker()() as db:
        cook = await db.get(Cook, uuid.UUID(k.cooks["Ramesh ji"]["id"]))
        ticket = await db.get(Ticket, uuid.UUID(t["id"]))
        assert cook is not None and cook.on_duty and cook.off_duty_until is None
        assert ticket is not None and str(ticket.assignee_cook_id) == mummy["id"]
    assert "cook_on_duty" in await _events(k)
