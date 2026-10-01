"""Worker sweeps after the Council review (H1, M6, M7, M9, M10; primary #4)."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import (
    AuthSession,
    ExportJob,
    Household,
    InboxItem,
    NotificationMark,
    OtpRequest,
    PushOutbox,
    Ticket,
)
from app.services import notifications as notify
from app.services import ticket_timers
from app.workers import worker
from tests.conftest import Login
from tests.kitchen_fixtures import Kitchen, make_kitchen


async def _run(now: datetime) -> ticket_timers.SweepReport:
    async with get_sessionmaker()() as db:
        report = await ticket_timers.run_all(db, now)
        await db.commit()
    return report


def _due(t: dict[str, Any]) -> datetime:
    return datetime.fromisoformat(t["due_at"])


async def _events(k: Kitchen, headers: dict[str, str] | None = None) -> list[str]:
    return [
        i["event"] for i in (await k.client.get("/v1/inbox", headers=headers or k.admin)).json()
    ]


async def test_no_show_has_a_lookback_and_reaches_the_backup(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    await k.invite_member()
    await k.add_family("Mummy")
    await k.patch_cook("Mummy", is_backup=True)
    t = await k.ticket(["gatte"])
    due = _due(t)
    # After an outage: 7 h past due is outside the 6 h lookback -> no alert on history.
    assert (await _run(due + timedelta(hours=7))).no_show == []
    # Within the window it fires (backup is a profile-only family cook -> admin gets it).
    t2 = await k.ticket(["bhindi"], slot="dinner")
    report = await _run(_due(t2) - timedelta(minutes=90))
    assert uuid.UUID(t2["id"]) in report.no_show
    assert "no_show" in await _events(k)


async def test_per_slot_thresholds(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    r = await client.patch(
        "/v1/households/me",
        json={"slot_defaults": {"lunch": {"no_show_minutes": 30}}},
        headers=k.admin,
    )
    assert r.status_code == 200, r.text
    t = await k.ticket(["gatte"])  # lunch
    due = _due(t)
    assert (await _run(due - timedelta(minutes=90))).no_show == []
    assert (await _run(due - timedelta(minutes=30))).no_show == [uuid.UUID(t["id"])]


async def test_accepted_not_cooking_is_at_risk_once(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook_h = await k.cook_login()
    t = await k.ticket(["gatte"])
    assert (await k.move(t, "accepted", cook_h)).status_code == 200
    due = _due(t)
    assert (await _run(due - timedelta(minutes=46))).at_risk == []
    assert (await _run(due - timedelta(minutes=45))).at_risk == [uuid.UUID(t["id"])]
    assert (await _run(due - timedelta(minutes=30))).at_risk == []
    assert "at_risk" in await _events(k)
    assert "at_risk" in await _events(k, cook_h)
    # Cooking in time: no alert.
    t2 = await k.ticket(["bhindi"], slot="dinner")
    await k.move(t2, "accepted", cook_h)
    await k.move(t2, "cooking", cook_h)
    assert (await _run(_due(t2) - timedelta(minutes=10))).at_risk == []


async def test_stuck_tickets_are_cancelled_24h_after_due(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t = await k.ticket(["gatte"])  # no cook -> unassigned
    assert t["status"] == "unassigned"
    due = _due(t)
    assert (await _run(due + timedelta(hours=23))).stuck_cancelled == []
    report = await _run(due + timedelta(hours=24))
    assert report.stuck_cancelled == [uuid.UUID(t["id"])]
    after = await k.get(t)
    assert after["status"] == "cancelled" and after["change_log"][-1]["action"] == "auto_closed"


async def test_one_failure_does_not_stop_the_sweep(
    client: AsyncClient, login: Login, monkeypatch: pytest.MonkeyPatch
) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    t1 = await k.ticket(["gatte"])
    t2 = await k.ticket(["bhindi"], slot="dinner")
    real = notify.emit
    calls = {"n": 0}

    async def flaky(*args: Any, **kwargs: Any) -> Any:
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("boom")
        return await real(*args, **kwargs)

    monkeypatch.setattr(notify, "emit", flaky)
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "TICKET_ALERT_LOOKBACK_HOURS", 12)
    later = max(_due(t1), _due(t2)) - timedelta(minutes=10)
    report = await _run(later)
    assert report.failed["no_show"] == 1 and len(report.no_show) == 1
    # The failed one was rolled back and is picked up by the next run.
    monkeypatch.setattr(notify, "emit", real)
    assert len((await _run(later + timedelta(minutes=5))).no_show) == 1
    async with get_sessionmaker()() as db:
        alerted = (
            await db.execute(
                select(func.count())
                .select_from(Ticket)
                .where(Ticket.no_show_alerted_at.is_not(None))
            )
        ).scalar_one()
    assert alerted == 2


async def test_tomorrow_uses_notification_marks(client: AsyncClient, login: Login) -> None:
    from tests.kitchen_fixtures import IST, future_day

    k = await make_kitchen(client, login)
    await k.add_hired()
    await k.cook_login()
    day = future_day(2)
    await k.ticket(["gatte"], day=day)
    eve = datetime.combine(day - timedelta(days=1), datetime.min.time(), tzinfo=IST)
    assert len((await _run(eve.replace(hour=20))).tomorrow_notified) == 1
    assert (await _run(eve.replace(hour=21))).tomorrow_notified == []
    async with get_sessionmaker()() as db:
        mark = (await db.execute(select(NotificationMark))).scalar_one()
        assert mark.kind == "tomorrow_tickets" and mark.local_date == eve.date()


async def test_push_goes_through_the_outbox(client: AsyncClient, login: Login) -> None:
    push = notify.NoopPush()
    notify.set_push(push)
    try:
        k = await make_kitchen(client, login)
        await client.post(
            "/v1/devices",
            json={"platform": "android", "push_token": "tok-admin-1", "app_version": "1"},
            headers=k.admin,
        )
        member = await k.invite_member()
        await k.ticket(["gatte"], headers=member)  # unassigned -> admin
        assert push.sent and push.sent[-1].data["event"] == "ticket_unassigned"
        async with get_sessionmaker()() as db:
            rows = list((await db.execute(select(PushOutbox))).scalars())
        assert rows and all(r.sent_at is not None for r in rows)
    finally:
        notify.set_push(None)


async def test_housekeeping_purge(client: AsyncClient, login: Login, tmp_path: Any) -> None:
    k = await make_kitchen(client, login)
    r = await client.post("/v1/export", headers=k.admin)
    assert r.status_code == 202
    again = await client.post("/v1/export", headers=k.admin)
    assert again.status_code == 202
    old = utcnow() - timedelta(days=100)
    async with get_sessionmaker()() as db:
        hid = (await db.execute(select(Household.id))).scalar_one()
        user_id = (await db.execute(select(AuthSession.user_id))).scalars().first()
        assert user_id is not None
        db.add(OtpRequest(phone="+919800000999", code_hash="x", expires_at=old, created_at=old))
        db.add(InboxItem(household_id=hid, user_id=user_id, event="x", title="old", created_at=old))
        for job in (await db.execute(select(ExportJob))).scalars():
            job.finished_at = old
        await db.commit()
        jobs_before = (await db.execute(select(func.count()).select_from(ExportJob))).scalar_one()
    assert jobs_before == 2  # inline run: the first job was done, not pending
    out = await worker.purge_housekeeping({})
    assert out["otp_requests"] >= 1 and out["inbox_items"] == 1 and out["exports"] == 2
    async with get_sessionmaker()() as db:
        assert (await db.execute(select(func.count()).select_from(ExportJob))).scalar_one() == 0


def test_worker_has_explicit_timeouts() -> None:
    from app.core.config import get_settings

    s = get_settings()
    assert worker.WorkerSettings.job_timeout == s.WORKER_JOB_TIMEOUT_SECONDS < 300
    names = {c.name.split(".")[-1]: c for c in worker.WorkerSettings.cron_jobs}
    assert names["cron:run_ticket_timers"].timeout_s == s.WORKER_JOB_TIMEOUT_SECONDS


async def test_one_pending_export_per_household(client: AsyncClient, login: Login) -> None:
    from app.models import ExportStatus

    k = await make_kitchen(client, login)
    async with get_sessionmaker()() as db:
        hid = (await db.execute(select(Household.id))).scalar_one()
        job = ExportJob(household_id=hid, status=ExportStatus.pending, created_at=utcnow())
        db.add(job)
        await db.commit()
        jid = str(job.id)
    r = await client.post("/v1/export", headers=k.admin)
    assert r.status_code == 202 and r.json()["id"] == jid and r.json()["status"] == "pending"
    assert (await client.get("/v1/export", headers=k.admin)).status_code == 405
