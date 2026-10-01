"""Phase 7: subscription lifecycle (trial -> active -> grace -> expired), restore, Play RTDN and
App Store v2 webhooks, read-only gating (402) with the cook exception, trial reminders,
consent, data export and the extended purge."""

from __future__ import annotations

import asyncio
import base64
import json
import uuid
from datetime import UTC, datetime, time, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import (
    Approval,
    ChatSession,
    Consent,
    ExportJob,
    Household,
    InboxItem,
    Rating,
    RationRequest,
    ServedHistory,
    StockItem,
    Subscription,
    SubscriptionStatus,
)
from app.services import export as export_svc
from app.services import subscription as sub_svc
from app.services.store_jws import AppleJwsDecoder
from app.workers.worker import purge_deleted
from tests.conftest import Login
from tests.kitchen_fixtures import IST, make_kitchen
from tests.pantry_fixtures import (
    complete,
    hired_ticket,
    household_id,
    inbox,
    ing,
    set_subscription,
)
from tests.store_certs import make_pki

S = SubscriptionStatus


async def _sub(hid: uuid.UUID) -> Subscription:
    async with get_sessionmaker()() as db:
        return (
            await db.execute(select(Subscription).where(Subscription.household_id == hid))
        ).scalar_one()


# ---- state machine (pure) --------------------------------------------------------------------


def test_effective_transitions() -> None:
    now = datetime(2026, 9, 26, 12, tzinfo=UTC)
    trial = Subscription(status=S.trial, trial_ends_at=now + timedelta(days=1))
    assert sub_svc.effective(trial, now).status == S.trial
    assert sub_svc.effective(trial, now + timedelta(days=1)).status == S.expired
    active = Subscription(status=S.active, renews_at=now)
    state = sub_svc.effective(active, now + timedelta(hours=1))
    assert state.status == S.grace and state.grace_until == now + timedelta(days=3)
    assert sub_svc.effective(active, now + timedelta(days=3)).status == S.expired
    assert sub_svc.refresh(active, now + timedelta(days=1)) and active.status == S.grace
    view = sub_svc.view(active, now + timedelta(days=1))
    assert view["read_only"] is False and view["days_left"] == 2


# ---- API ---------------------------------------------------------------------------------------


async def test_trial_restore_and_one_trial_per_phone(
    client: AsyncClient, login: Login, make_household: Any
) -> None:
    admin = await make_household("+919800000201", "Ghar A")
    r = await client.get("/v1/subscription", headers=admin)
    body = r.json()
    assert body["status"] == "trial" and body["read_only"] is False and body["days_left"] == 7
    ends = datetime.fromisoformat(body["trial_ends_at"])
    assert timedelta(days=6, hours=23) < ends - utcnow() <= timedelta(days=7)

    r = await client.post(
        "/v1/subscription/restore",
        json={"store": "play", "purchase_token": "invalid-x"},
        headers=admin,
    )
    assert r.status_code == 422 and r.json()["code"] == "receipt_invalid"
    r = await client.post(
        "/v1/subscription/restore",
        json={"store": "play", "purchase_token": "demo-stub-purchase-token"},
        headers=admin,
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "active" and r.json()["product_id"] == "banega_weekly_50"
    assert r.json()["store"] == "play"
    r = await client.post(
        "/v1/subscription/restore",
        json={"store": "appstore", "receipt": "stub-receipt"},
        headers=admin,
    )
    assert r.status_code == 200 and r.json()["store"] == "app_store"

    # The same purchase cannot back a second household.
    other = await make_household("+919800000202", "Ghar B")
    r = await client.post(
        "/v1/subscription/restore",
        json={"store": "play", "purchase_token": "demo-stub-purchase-token"},
        headers=other,
    )
    assert r.status_code == 409 and r.json()["code"] == "purchase_in_other_household"

    # A second household from the same phone starts without a trial (F-3-03).
    assert (await client.delete("/v1/household", headers=other)).status_code == 200
    r = await client.post("/v1/households", json={"name": "Ghar C"}, headers=other)
    assert r.status_code == 201
    assert r.json()["subscription"]["status"] == "expired"
    assert (await client.get("/v1/subscription", headers=other)).json()["read_only"] is True


def _pubsub(payload: dict[str, Any]) -> dict[str, Any]:
    data = base64.b64encode(json.dumps(payload).encode()).decode()
    return {"message": {"data": data, "messageId": "1"}, "subscription": "projects/x/subs/y"}


def _jws(payload: dict[str, Any]) -> str:
    def seg(obj: dict[str, Any]) -> str:
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")

    return f"{seg({'alg': 'ES256'})}.{seg(payload)}.sig"


async def test_play_webhook_moves_status(
    client: AsyncClient, make_household: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    admin = await make_household("+919800000211")
    await client.post(
        "/v1/subscription/restore",
        json={"store": "play", "purchase_token": "tok-1"},
        headers=admin,
    )
    monkeypatch.setattr(get_settings(), "PLAY_WEBHOOK_SECRET", "s3cret")
    ms = int(utcnow().timestamp() * 1000)

    def note(ntype: int, offset: int) -> dict[str, Any]:
        return _pubsub(
            {
                "packageName": "app.banega",
                "eventTimeMillis": str(ms + offset),
                "subscriptionNotification": {
                    "notificationType": ntype,
                    "purchaseToken": "tok-1",
                    "subscriptionId": "banega_weekly_50",
                },
            }
        )

    r = await client.post("/v1/webhooks/play", json=note(6, 1000))
    assert r.status_code == 401
    # The secret is never accepted from the query string (it would land in access logs).
    r = await client.post("/v1/webhooks/play?token=s3cret", json=note(6, 1000))
    assert r.status_code == 401
    secret = {"X-Webhook-Secret": "s3cret"}
    r = await client.post(
        "/v1/webhooks/play", json=note(6, 1000), headers={"X-Webhook-Secret": "s3cret"}
    )
    assert r.status_code == 200 and r.json()["result"] == "grace"
    assert (await client.get("/v1/subscription", headers=admin)).json()["status"] == "grace"
    # Older events are ignored; Pub/Sub may redeliver out of order.
    r = await client.post("/v1/webhooks/play", json=note(2, 0), headers=secret)
    assert r.json()["result"] == "stale"
    r = await client.post("/v1/webhooks/play", json=note(13, 2000), headers=secret)
    assert r.json()["result"] == "expired"
    assert (await client.get("/v1/subscription", headers=admin)).json()["read_only"] is True
    r = await client.post("/v1/webhooks/play", json=note(2, 3000), headers=secret)
    assert r.json()["result"] == "active"
    r = await client.post(
        "/v1/webhooks/play",
        json=_pubsub({"subscriptionNotification": {"notificationType": 2, "purchaseToken": "?"}}),
        headers=secret,
    )
    assert r.json()["result"] == "unknown"


def _appstore_body(
    sign: Any, hid: uuid.UUID, ntype: str, subtype: str = "", at: int = 0, **extra: Any
) -> dict[str, Any]:
    expires = int((utcnow() + timedelta(days=7)).timestamp() * 1000)
    info = sign(
        {
            "originalTransactionId": "2000000123",
            "productId": "banega_weekly_50",
            "expiresDate": expires,
            "appAccountToken": str(hid),
            "bundleId": "app.banega",
            "environment": "Production",
        }
    )
    payload = {
        "notificationType": ntype,
        "subtype": subtype,
        "signedDate": int(utcnow().timestamp() * 1000) + at,
        "data": {
            "signedTransactionInfo": info,
            "bundleId": "app.banega",
            "environment": "Production",
            **extra,
        },
    }
    return {"signedPayload": sign(payload), "_expires": expires}


@pytest.fixture
def apple_pki() -> Any:
    pki = make_pki()
    sub_svc.set_jws_decoder(
        AppleJwsDecoder([pki.root], bundle_id="app.banega", environment="Production")
    )
    yield pki
    sub_svc.set_jws_decoder(None)


async def test_appstore_webhook(client: AsyncClient, make_household: Any, apple_pki: Any) -> None:
    admin = await make_household("+919800000221")
    hid = uuid.UUID(
        (await client.get("/v1/households/me", headers=admin)).json()["household"]["id"]
    )

    def body(ntype: str, subtype: str = "", at: int = 0) -> dict[str, Any]:
        out = _appstore_body(apple_pki.sign, hid, ntype, subtype, at)
        out.pop("_expires")
        return out

    first = _appstore_body(apple_pki.sign, hid, "SUBSCRIBED", at=1)
    expires = first.pop("_expires")
    r = await client.post("/v1/webhooks/appstore", json=first)
    assert r.status_code == 200 and r.json()["result"] == "active"
    sub = await _sub(hid)
    assert sub.original_transaction_id == "2000000123" and sub.store == "app_store"
    assert abs((sub.renews_at or utcnow()).timestamp() * 1000 - expires) < 1000
    r = await client.post(
        "/v1/webhooks/appstore", json=body("DID_FAIL_TO_RENEW", "GRACE_PERIOD", 2)
    )
    assert r.json()["result"] == "grace"
    r = await client.post("/v1/webhooks/appstore", json=body("EXPIRED", at=3))
    assert r.json()["result"] == "expired"
    r = await client.post("/v1/webhooks/appstore", json={"signedPayload": "not-a-jws"})
    assert r.status_code == 401 and r.json()["code"] == "invalid_signature"


async def test_appstore_webhook_rejects_forged_and_foreign_signatures(
    client: AsyncClient, make_household: Any, apple_pki: Any
) -> None:
    admin = await make_household("+919800000222")
    hid = uuid.UUID(
        (await client.get("/v1/households/me", headers=admin)).json()["household"]["id"]
    )
    # Unsigned (the old dev decoder format): refused, appAccountToken never resolved.
    unsigned = {"signedPayload": _jws({"notificationType": "REVOKE", "data": {}})}
    r = await client.post("/v1/webhooks/appstore", json=unsigned)
    assert r.status_code == 401
    # Signed by a chain that does not end in our root.
    stranger = make_pki()
    forged = _appstore_body(stranger.sign, hid, "REVOKE")
    forged.pop("_expires")
    r = await client.post("/v1/webhooks/appstore", json=forged)
    assert r.status_code == 401
    assert r.json()["details"]["reason"] in ("untrusted_root", "chain_signature")
    # Our leaf key but a tampered payload segment.
    good = _appstore_body(apple_pki.sign, hid, "SUBSCRIBED")
    good.pop("_expires")
    head, _, sig = good["signedPayload"].split(".")
    evil = base64.urlsafe_b64encode(json.dumps({"notificationType": "REVOKE"}).encode())
    tampered = {"signedPayload": f"{head}.{evil.decode().rstrip('=')}.{sig}"}
    r = await client.post("/v1/webhooks/appstore", json=tampered)
    assert r.status_code == 401 and r.json()["details"]["reason"] == "signature"
    # Another app's notification.
    other = _appstore_body(apple_pki.sign, hid, "REVOKE", bundleId="com.other")
    other.pop("_expires")
    r = await client.post("/v1/webhooks/appstore", json=other)
    assert r.status_code == 401 and r.json()["details"]["reason"] == "bundle_id"
    # Expired leaf certificate.
    old = make_pki(leaf_expired=True)
    sub_svc.set_jws_decoder(AppleJwsDecoder([old.root], bundle_id="app.banega"))
    stale = _appstore_body(old.sign, hid, "REVOKE")
    stale.pop("_expires")
    r = await client.post("/v1/webhooks/appstore", json=stale)
    assert r.status_code == 401 and r.json()["details"]["reason"] == "certificate_expired"
    assert (await client.get("/v1/subscription", headers=admin)).json()["status"] == "trial"


async def test_unverified_decoder_never_resolves_app_account_token(
    client: AsyncClient, make_household: Any
) -> None:
    """Dev/test decoder: payloads are read, but appAccountToken (a household id anyone can
    put in an unsigned payload) is ignored; only a known originalTransactionId matches."""
    admin = await make_household("+919800000223")
    hid = uuid.UUID(
        (await client.get("/v1/households/me", headers=admin)).json()["household"]["id"]
    )
    body = _appstore_body(_jws, hid, "REVOKE")
    body.pop("_expires")
    r = await client.post("/v1/webhooks/appstore", json=body)
    assert r.status_code == 200 and r.json()["result"] == "unknown"
    assert (await client.get("/v1/subscription", headers=admin)).json()["status"] == "trial"


def test_bundled_apple_root_is_apple_root_ca_g3() -> None:
    from cryptography.hazmat.primitives import hashes

    from app.services.store_jws import _root_from_path

    root = _root_from_path(get_settings().APPSTORE_ROOT_CERT_PATH)
    assert root.fingerprint(hashes.SHA256()).hex().upper() == (
        "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179"
    )


async def test_expired_is_read_only_except_cook_work_today_tomorrow(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    hid = await household_id(k)
    later, cook_h = await hired_ticket(k)  # 2 days out
    tomorrow = datetime.now(IST).date() + timedelta(days=1)
    menu = await k.menu(["gatte"], day=tomorrow, slot="dinner")
    soon = (await k.confirm(menu)).json()["ticket"]

    await set_subscription(hid, status=S.expired)
    r = await client.put(
        f"/v1/menus/{tomorrow.isoformat()}/lunch/dishes",
        json={"recipe_ids": [str(k.recipes["gatte"])]},
        headers=k.admin,
    )
    assert r.status_code == 402 and r.json()["code"] == "subscription_expired"
    assert (await client.post("/v1/chat/sessions", json={}, headers=k.admin)).status_code == 402
    r = await client.patch(f"/v1/tickets/{soon['id']}", json={"notes": "x"}, headers=k.admin)
    assert r.status_code == 402
    # Reads keep working; so do the cook's actions on tomorrow's ticket ...
    assert (await client.get(f"/v1/tickets/{later['id']}", headers=k.admin)).status_code == 200
    assert (
        await client.get("/v1/menus?date=" + tomorrow.isoformat(), headers=k.admin)
    ).status_code == 200
    assert (await k.move(soon, "accepted", cook_h)).status_code == 200
    r = await client.post(f"/v1/tickets/{soon['id']}/items/{await ing('curd')}/out", headers=cook_h)
    assert r.status_code == 200
    # ... but not on a ticket two days out.
    r = await k.move(later, "accepted", cook_h)
    assert r.status_code == 402
    # Paying again lifts it.
    r = await client.post(
        "/v1/subscription/restore",
        json={"store": "play", "purchase_token": "tok-rescue"},
        headers=k.admin,
    )
    assert r.json()["status"] == "active"
    assert (await k.move(later, "accepted", cook_h)).status_code == 200


async def test_trial_reminders_day_5_and_7_at_10(client: AsyncClient, make_household: Any) -> None:
    admin = await make_household("+919800000231")
    hid = uuid.UUID(
        (await client.get("/v1/households/me", headers=admin)).json()["household"]["id"]
    )
    tz = ZoneInfo("Asia/Kolkata")
    start = datetime.combine(datetime.now(tz).date(), time(9, 0), tzinfo=tz)
    await set_subscription(hid, trial_ends_at=start + timedelta(days=7))

    async def sweep(at: datetime) -> dict[str, int]:
        async with get_sessionmaker()() as db:
            out = await sub_svc.sweep(db, at)
            await db.commit()
        return out

    day5 = datetime.combine(start.date() + timedelta(days=4), time(9, 59), tzinfo=tz)
    assert (await sweep(day5))["expiry_reminders"] == 0
    assert (await sweep(day5 + timedelta(minutes=1)))["expiry_reminders"] == 1
    assert (await sweep(day5 + timedelta(hours=3)))["expiry_reminders"] == 0  # once
    assert (await sweep(day5 + timedelta(days=1, minutes=1)))["expiry_reminders"] == 0  # day 6
    day7 = datetime.combine(start.date() + timedelta(days=6), time(10, 5), tzinfo=tz)
    assert (await sweep(day7))["expiry_reminders"] == 1
    items = [i for i in await inbox_items(hid) if i.event == "expiry_reminder"]
    assert len(items) == 2
    # After the end the sweep persists the transition.
    out = await sweep(start + timedelta(days=7, minutes=1))
    assert out["subscriptions_changed"] == 1 and (await _sub(hid)).status == S.expired


async def inbox_items(hid: uuid.UUID) -> list[InboxItem]:
    async with get_sessionmaker()() as db:
        return list(
            (await db.execute(select(InboxItem).where(InboxItem.household_id == hid))).scalars()
        )


async def test_consent(client: AsyncClient, login: Login) -> None:
    h = await login("+919800000241")
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["consent"]["required"] is True and me["consent"]["current_version"] == "2026-09"
    assert me["user"]["language"] == "hi_Latn"
    r = await client.post("/v1/consent", json={"version": "2019-01"}, headers=h)
    assert r.status_code == 422 and r.json()["code"] == "unknown_consent_version"
    r = await client.post("/v1/consent", json={"version": "2026-09"}, headers=h)
    assert r.status_code == 200 and r.json()["required"] is False
    assert (
        await client.post("/v1/consent", json={"version": "2026-09"}, headers=h)
    ).status_code == 200
    # Accepted before the household existed: it moves into the new household.
    r = await client.post("/v1/households", json={"name": "Naya ghar"}, headers=h)
    assert r.json()["consent"]["version"] == "2026-09"
    assert (await client.get("/v1/me", headers=h)).json()["consent"]["required"] is False
    r = await client.patch("/v1/me", json={"language": "en"}, headers=h)
    assert r.json()["user"]["language"] == "en" and r.json()["user"]["locale"] == "en"


async def test_export_job_and_download(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)
    await complete(k, t, cook_h)
    member = await k.invite_member()
    assert (await client.post("/v1/export", headers=member)).status_code == 403
    r = await client.post("/v1/export", headers=k.admin)
    assert r.status_code == 202, r.text
    job = r.json()
    assert job["status"] == "done" and job["download_url"].endswith("/download")
    note = next(i for i in await inbox(k, k.admin) if i["event"] == "export_ready")
    assert note["link"] == job["download_url"]
    r = await client.get(job["download_url"], headers=k.admin)
    assert r.status_code == 200
    data = r.json()
    assert data["household"]["name"] == "Test ghar"
    assert [x["id"] for x in data["tickets"]] == [t["id"]]
    assert {m["name"] for m in data["members"]} >= {"Papa", "Mummy"}
    assert all("phone" not in c for c in data["cooks"])
    status = (await client.get(f"/v1/export/{job['id']}", headers=k.admin)).json()
    assert status["status"] == "done"
    hid = await household_id(k)
    assert export_svc.household_dir(hid).exists()


async def test_purge_removes_every_household_table(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    hid = await household_id(k)
    t, cook_h = await hired_ticket(k)
    await client.get("/v1/stock", headers=k.admin)
    await client.post("/v1/ration-requests", json={"items": [{"name": "dahi"}]}, headers=cook_h)
    await client.post(f"/v1/tickets/{t['id']}/items/{await ing('curd')}/out", headers=cook_h)
    await complete(k, t, cook_h)
    gatte = next(d["recipe_id"] for d in t["dishes"] if d["name"].startswith("Gatte"))
    r = await client.post(
        f"/v1/tickets/{t['id']}/ratings",
        json={"ratings": [{"recipe_id": gatte, "member_id": k.members["Papa"], "score": 3}]},
        headers=k.admin,
    )
    assert r.status_code == 200
    await client.post("/v1/consent", json={"version": "2026-09"}, headers=k.admin)
    assert (await client.post("/v1/chat/sessions", json={}, headers=k.admin)).status_code == 200
    assert (await client.post("/v1/export", headers=k.admin)).status_code == 202
    folder = export_svc.household_dir(hid)
    assert folder.exists()

    models: tuple[Any, ...] = (
        StockItem,
        RationRequest,
        Approval,
        Rating,
        ServedHistory,
        Consent,
        ExportJob,
        ChatSession,
        InboxItem,
    )

    async def counts() -> dict[str, int]:
        out = {}
        async with get_sessionmaker()() as db:
            for m in models:
                n = (
                    await db.execute(
                        select(func.count()).select_from(m).where(m.household_id == hid)
                    )
                ).scalar_one()
                out[m.__name__] = int(n)
        return out

    before = await counts()
    assert all(v > 0 for v in before.values()), before

    assert (await client.delete("/v1/household", headers=k.admin)).status_code == 200
    async with get_sessionmaker()() as db:
        h = await db.get(Household, hid)
        assert h is not None
        h.deleted_at = utcnow() - timedelta(days=8)
        await db.commit()
    result = await purge_deleted({})
    assert result["households"] == 1
    assert set((await counts()).values()) == {0}
    assert not await asyncio.to_thread(Path(folder).exists)
