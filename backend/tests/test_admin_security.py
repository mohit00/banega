"""Admin hardening (review B2/B3, H4): staff accounts + TOTP + lockout, audit log on every
change, soft deletes instead of SQL DELETE."""

from __future__ import annotations

import sys
from collections.abc import AsyncIterator
from datetime import timedelta
from pathlib import Path
from typing import Any

import pyotp
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import (
    AuditLog,
    Cook,
    CookKind,
    Household,
    Ingredient,
    StaffUser,
    Ticket,
    TicketStatus,
    User,
)
from app.services import staff as staff_svc
from tests.test_admin import _admin_module

PASSWORD = "correct horse battery"


async def _make_staff(email: str = "ops@banega.app", *, enrolled: bool = True) -> StaffUser:
    async with get_sessionmaker()() as db:
        staff = await staff_svc.create_staff(db, email, PASSWORD)
        if enrolled:
            staff.totp_enrolled_at = utcnow()
        await db.commit()
        return staff


def _code(staff: StaffUser, offset: int = 0) -> str:
    totp = pyotp.TOTP(staff.totp_secret)
    return totp.at(utcnow() + timedelta(seconds=offset * totp.interval))


@pytest.fixture
async def anon(tmp_path: Path) -> AsyncIterator[AsyncClient]:
    module = _admin_module(tmp_path)
    app = module.create_app()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def _login(c: AsyncClient, email: str, password: str, code: str = "") -> Any:
    await c.get("/admin/login")
    token = c.cookies.get("starlette_admin_csrftoken") or ""
    return await c.post(
        "/admin/login",
        data={"username": email, "password": password, "totp": code, "csrftoken": token},
        follow_redirects=False,
    )


def _csrf(c: AsyncClient) -> dict[str, str]:
    return {"X-CSRFToken": c.cookies.get("starlette_admin_csrftoken") or ""}


async def test_login_needs_password_and_totp(anon: AsyncClient) -> None:
    staff = await _make_staff()
    r = await _login(anon, "OPS@banega.app", PASSWORD, "000000")
    assert r.status_code == 400 and "Invalid" in r.text
    r = await _login(anon, "ops@banega.app", "wrong password!!", _code(staff))
    assert r.status_code == 400
    r = await _login(anon, "ops@banega.app", PASSWORD, _code(staff))
    assert r.status_code == 303, r.text[:300]
    assert (await anon.get("/admin/user/list")).status_code == 200
    async with get_sessionmaker()() as db:
        row = await db.get(StaffUser, staff.id)
        assert row is not None and row.last_login is not None
        login = (await db.execute(select(AuditLog).where(AuditLog.action == "login"))).scalar_one()
        assert login.staff_id == staff.id


async def test_totp_code_cannot_be_replayed(anon: AsyncClient) -> None:
    staff = await _make_staff()
    code = _code(staff)
    assert (await _login(anon, staff.email, PASSWORD, code)).status_code == 303
    await anon.post("/admin/logout", headers=_csrf(anon))
    anon.cookies.clear()
    assert (await _login(anon, staff.email, PASSWORD, code)).status_code == 400


async def test_lockout_after_five_failures(anon: AsyncClient) -> None:
    staff = await _make_staff()
    for _ in range(5):
        assert (await _login(anon, staff.email, "nope nope nope", "")).status_code == 400
    r = await _login(anon, staff.email, PASSWORD, _code(staff))
    assert r.status_code == 400 and "Too many failed attempts" in r.text


async def test_first_login_enrols_and_shows_uri_once(anon: AsyncClient) -> None:
    staff = await _make_staff(enrolled=False)
    r = await _login(anon, staff.email, PASSWORD)
    assert r.status_code == 303 and r.headers["location"].endswith("/admin/enroll")
    page = await anon.get("/admin/enroll")
    assert page.status_code == 200 and "otpauth://totp/" in page.text
    assert staff.totp_secret in page.text
    again = await anon.get("/admin/enroll")
    assert "otpauth://" not in again.text and "already shown" in again.text
    # Not logged in yet.
    assert (await anon.get("/admin/user/list", follow_redirects=False)).status_code in (302, 303)
    token = anon.cookies.get("starlette_admin_csrftoken") or ""
    bad = await anon.post("/admin/enroll", data={"totp": "123456", "csrftoken": token})
    assert bad.status_code == 400
    ok = await anon.post(
        "/admin/enroll", data={"totp": _code(staff), "csrftoken": token}, follow_redirects=False
    )
    assert ok.status_code == 303
    assert (await anon.get("/admin/user/list")).status_code == 200
    async with get_sessionmaker()() as db:
        row = await db.get(StaffUser, staff.id)
        assert row is not None and row.totp_enrolled_at is not None


async def test_env_credential_only_without_staff(anon: AsyncClient) -> None:
    await _make_staff()
    r = await _login(anon, "admin", "test-admin-password")
    assert r.status_code == 400


async def test_deactivated_staff_loses_access(anon: AsyncClient) -> None:
    staff = await _make_staff()
    assert (await _login(anon, staff.email, PASSWORD, _code(staff))).status_code == 303
    async with get_sessionmaker()() as db:
        row = await db.get(StaffUser, staff.id)
        assert row is not None
        row.is_active = False
        await db.commit()
    r = await anon.get("/admin/user/list", follow_redirects=False)
    assert r.status_code in (302, 303)


@pytest.fixture
async def staff_client(anon: AsyncClient) -> tuple[AsyncClient, StaffUser]:
    staff = await _make_staff()
    assert (await _login(anon, staff.email, PASSWORD, _code(staff))).status_code == 303
    return anon, staff


async def test_admin_deletes_are_soft_and_audited(
    staff_client: tuple[AsyncClient, StaffUser], client: AsyncClient, make_household: Any
) -> None:
    c, staff = staff_client
    headers = await make_household("+919800000501")
    me = (await client.get("/v1/me", headers=headers)).json()
    uid = me["user"]["id"]
    hid = me["membership"]["household_id"]
    r = await c.post(
        "/admin/_api/user/action", params={"name": "delete", "pks": [uid]}, headers=_csrf(c)
    )
    assert r.status_code == 200, r.text
    r = await c.post(
        "/admin/_api/household/action", params={"name": "delete", "pks": [hid]}, headers=_csrf(c)
    )
    assert r.status_code == 200, r.text
    async with get_sessionmaker()() as db:
        user = (await db.execute(select(User).where(User.phone == "+919800000501"))).scalar_one()
        household = (await db.execute(select(Household))).scalar_one()
        assert user.deleted_at is not None and household.deleted_at is not None
        rows = list(
            (await db.execute(select(AuditLog).where(AuditLog.action == "soft_delete"))).scalars()
        )
        assert {r.model for r in rows} == {"User", "Household"}
        assert all(r.staff_id == staff.id for r in rows)
        user_row = next(r for r in rows if r.model == "User")
        assert user_row.before is not None and user_row.before["deleted_at"] is None
        assert user_row.after is not None and user_row.after["deleted_at"] is not None
    # The user's sessions were revoked (same as DELETE /v1/me).
    assert (await client.get("/v1/me", headers=headers)).status_code == 401


async def test_admin_cook_delete_goes_through_remove_cook(
    staff_client: tuple[AsyncClient, StaffUser], client: AsyncClient, login: Any
) -> None:
    from tests.kitchen_fixtures import make_kitchen
    from tests.pantry_fixtures import hired_ticket

    c, _ = staff_client
    k = await make_kitchen(client, login)
    ticket, _cook_h = await hired_ticket(k)
    assert ticket["status"] == "new"
    async with get_sessionmaker()() as db:
        cook = (await db.execute(select(Cook).where(Cook.kind == CookKind.hired))).scalar_one()
    r = await c.post(
        "/admin/_api/cook/action",
        params={"name": "delete", "pks": [str(cook.id)]},
        headers=_csrf(c),
    )
    assert r.status_code == 200, r.text
    async with get_sessionmaker()() as db:
        row = await db.get(Cook, cook.id)
        assert row is not None and row.removed_at is not None
        t = (await db.execute(select(Ticket))).scalar_one()
        assert t.status == TicketStatus.unassigned and t.assignee_cook_id is None


async def test_admin_ingredient_delete_deactivates(
    staff_client: tuple[AsyncClient, StaffUser],
) -> None:
    from app.services.importer import seed_all

    c, _ = staff_client
    async with get_sessionmaker()() as db:
        await seed_all(db, publish="clean", with_demo_household=False)
        onion = (
            await db.execute(select(Ingredient).where(Ingredient.slug == "onion"))
        ).scalar_one()
    r = await c.post(
        "/admin/_api/ingredient/action",
        params={"name": "delete", "pks": [str(onion.id)]},
        headers=_csrf(c),
    )
    assert r.status_code == 200, r.text
    async with get_sessionmaker()() as db:
        row = await db.get(Ingredient, onion.id)
        assert row is not None and row.is_active is False


async def test_edits_are_audited_with_before_and_after(
    staff_client: tuple[AsyncClient, StaffUser],
) -> None:
    c, staff = staff_client
    other = await _make_staff("second@banega.app")
    await c.get(f"/admin/staff-user/edit?pk={other.id}")
    token = c.cookies.get("starlette_admin_csrftoken") or ""
    r = await c.post(
        f"/admin/staff-user/edit?pk={other.id}",
        data={"csrftoken": token},  # is_active unchecked -> False
        follow_redirects=False,
    )
    assert r.status_code in (302, 303), r.text[:500]
    async with get_sessionmaker()() as db:
        row = (await db.execute(select(AuditLog).where(AuditLog.action == "edit"))).scalar_one()
        assert row.model == "StaffUser" and row.pk == str(other.id)
        assert row.staff_id == staff.id and row.staff_email == staff.email
        assert row.before == {"is_active": True} or row.before["is_active"] is True
        assert row.after is not None and row.after["is_active"] is False
        assert "password_hash" not in (row.after or {})


async def test_cli_staff_create_prints_totp_uri(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    from app import cli
    from app.core import db as core_db

    async def _noop() -> None:
        return None

    monkeypatch.setattr(core_db, "dispose_engine", _noop)
    rc = await cli._staff_create("New@Banega.app", PASSWORD)
    out = capsys.readouterr().out
    assert rc == 0 and "otpauth://totp/" in out and "new%40banega.app" in out.lower()
    async with get_sessionmaker()() as db:
        staff = (await db.execute(select(StaffUser))).scalar_one()
        assert staff.email == "new@banega.app"
        assert staff.password_hash.startswith("$argon2id$")
        assert staff.totp_shown_at is not None and staff.totp_enrolled_at is None
    assert await cli._staff_create("new@banega.app", PASSWORD) == 2
    assert await cli._staff_create("x@banega.app", "short") == 2


def test_admin_dir_on_path() -> None:
    assert any(p.endswith("admin") for p in sys.path)
