"""Notification matrix (F-X-01 / contract), inbox, push adapter and preferences."""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from app.services import notifications as notify
from app.services.notifications import MATRIX, Audience, NoopPush, Role, resolve
from tests.conftest import Login
from tests.kitchen_fixtures import make_kitchen

A1, A2, M1, COOK, CONF, PRIM, BACK, REQ = (uuid.UUID(int=i) for i in range(1, 9))
AUD = Audience(
    admins=(A1, A2),
    members=(M1,),
    assignee=(COOK,),
    confirmer=CONF,
    primary=(PRIM,),
    backup=(BACK,),
    requester=(REQ,),
)

# The contract matrix, row by row.
CONTRACT: dict[str, list[uuid.UUID]] = {
    "ticket_created": [COOK],
    "ticket_accepted": [CONF],
    "ticket_updated": [COOK],
    "ticket_unassigned": [A1, A2],
    "ticket_completed": [CONF, A1, A2],
    "not_confirmed_prompt": [A1, A2],
    "cook_off_duty": [A1, A2],
    "no_show": [A1, A2, BACK],  # + backup cook (F-5.7-12)
    "stock_issue": [A1, A2, M1],
    "ration_request": [A1, A2],
    "tomorrow_tickets": [COOK],
    # Phase 6-7 contract rows.
    "stock_low": [A1, A2],
    "ration_decided": [REQ],
    "approval_request": [A1, A2, M1],
    "approval_decided": [REQ],
    "stock_issue_timeout": [A1, A2],
    "rate_prompt": [CONF, A1, A2],
    "expiry_reminder": [A1, A2],
    "weekly_summary": [A1, A2],
}


@pytest.mark.parametrize(("event", "expected"), sorted(CONTRACT.items()))
def test_contract_matrix_resolution(event: str, expected: list[uuid.UUID]) -> None:
    assert MATRIX[event].in_contract
    assert resolve(event, AUD) == expected
    assert set(MATRIX[event].channels) == {notify.Channel.push, notify.Channel.inbox}


def test_every_contract_event_is_in_the_matrix() -> None:
    assert set(CONTRACT) == {e for e, r in MATRIX.items() if r.in_contract}


def test_additive_events() -> None:
    assert resolve("ticket_cancelled", AUD) == [COOK]
    assert resolve("cook_message", AUD) == [A1, A2, CONF]
    assert resolve("family_message", AUD) == [COOK]
    assert resolve("chef_claimed", AUD) == [A1, A2, PRIM]
    assert resolve("cook_on_duty", AUD) == [A1, A2]
    assert resolve("ration_bought", AUD) == [REQ]
    assert resolve("stock_issue_resolved", AUD) == [A1, A2]
    assert resolve("export_ready", AUD) == [REQ]


def test_actor_is_never_notified_and_duplicates_collapse() -> None:
    aud = Audience(admins=(A1,), confirmer=A1)
    assert resolve("ticket_completed", aud) == [A1]
    assert resolve("ticket_completed", aud, actor_user_id=A1) == []


def test_cook_users_via_admin_goes_to_admins() -> None:
    from app.models import Cook, CookKind, CookLoginMode

    own = Cook(kind=CookKind.hired, user_id=COOK, login_mode=CookLoginMode.own)
    via = Cook(kind=CookKind.family, user_id=None, login_mode=CookLoginMode.via_admin)
    assert notify.cook_users(own, (A1,)) == (COOK,)
    assert notify.cook_users(via, (A1, A2)) == (A1, A2)
    assert notify.cook_users(None, (A1,)) == ()


def test_roles_cover_the_enum() -> None:
    used = {r for rule in MATRIX.values() for r in rule.roles}
    assert used <= set(Role)


def test_quiet_hours() -> None:
    q = {"start": "22:00", "end": "07:00"}
    at = datetime(2026, 9, 26, 17, 30, tzinfo=UTC)  # 23:00 IST
    assert notify.in_quiet_hours(q, at, "Asia/Kolkata")
    assert not notify.in_quiet_hours(q, datetime(2026, 9, 26, 6, 30, tzinfo=UTC), "Asia/Kolkata")
    assert not notify.in_quiet_hours(None, at, "Asia/Kolkata")


@pytest.fixture
def push() -> Iterator[NoopPush]:
    adapter = NoopPush()
    notify.set_push(adapter)
    yield adapter
    notify.set_push(None)


async def test_push_goes_to_devices_and_respects_prefs(
    client: AsyncClient, login: Login, push: NoopPush
) -> None:
    k = await make_kitchen(client, login)
    await client.post(
        "/v1/devices",
        json={"platform": "android", "push_token": "tok-admin", "app_version": "1"},
        headers=k.admin,
    )
    member = await k.invite_member()
    await k.ticket(["gatte"], headers=member)  # unassigned -> admin (not the confirmer)
    assert [m.title for m in push.sent][-1].endswith("ke liye koi cook nahi")
    assert push.sent[-1].tokens == (("android", "tok-admin"),)
    assert push.sent[-1].data["event"] == "ticket_unassigned"
    # Switch the event off: inbox still gets it, push does not.
    r = await client.put(
        "/v1/me/notification-prefs",
        json={"prefs": [{"event": "ticket_unassigned", "enabled": False}]},
        headers=k.admin,
    )
    assert r.status_code == 200
    prefs = {p["event"]: p for p in r.json()["prefs"]}
    assert prefs["ticket_unassigned"]["enabled"] is False
    n = len(push.sent)
    await k.ticket(["bhindi"], slot="dinner", headers=member)
    assert len(push.sent) == n
    inbox = (await client.get("/v1/inbox", headers=k.admin)).json()
    assert [i["event"] for i in inbox] == ["ticket_unassigned", "ticket_unassigned"]


async def test_mandatory_events_cannot_be_switched_off(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    r = await client.put(
        "/v1/me/notification-prefs",
        json={
            "prefs": [{"event": "ticket_created", "enabled": False}],
            "quiet_hours": {"start": "22:00", "end": "07:00"},
        },
        headers=k.admin,
    )
    body = r.json()
    created = next(p for p in body["prefs"] if p["event"] == "ticket_created")
    assert created == {"event": "ticket_created", "enabled": True, "mandatory": True}
    assert body["quiet_hours"] == {"start": "22:00", "end": "07:00"}
    r = await client.put(
        "/v1/me/notification-prefs", json={"prefs": [], "quiet_hours": None}, headers=k.admin
    )
    assert r.json()["quiet_hours"] is None
    r = await client.put(
        "/v1/me/notification-prefs",
        json={"prefs": [{"event": "nope", "enabled": False}]},
        headers=k.admin,
    )
    assert r.status_code == 404


async def test_inbox_paging_and_read(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    for slot in ("nashta", "lunch", "dinner"):
        await k.ticket(["poha" if slot == "nashta" else "gatte"], slot=slot, headers=member)
    r = await client.get("/v1/inbox?limit=2", headers=k.admin)
    assert len(r.json()) == 2 and r.headers.get("X-Next-Cursor")
    cursor = r.headers["X-Next-Cursor"]
    r2 = await client.get(f"/v1/inbox?limit=2&cursor={cursor}", headers=k.admin)
    assert len(r2.json()) == 1 and "X-Next-Cursor" not in r2.headers
    ids = [i["id"] for i in r.json() + r2.json()]
    assert len(set(ids)) == 3
    item = r.json()[0]
    assert item["read_at"] is None and item["title"] and item["ticket_id"]
    read = (await client.post(f"/v1/inbox/{item['id']}/read", headers=k.admin)).json()
    assert read["read_at"] is not None
    unread = (await client.get("/v1/inbox?unread=true", headers=k.admin)).json()
    assert item["id"] not in [i["id"] for i in unread]
    # Someone else's item is 404.
    assert (await client.post(f"/v1/inbox/{item['id']}/read", headers=member)).status_code == 404
