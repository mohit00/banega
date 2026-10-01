"""Admin panel security: per-staff login (email + password + TOTP, lockout), the audit hook
on every view, and soft deletes for accounts / households / members / cooks / ingredients.

The rules live in ``app.services.staff`` (unit-tested there); this module adapts them to
Starlette-Admin.
"""

from __future__ import annotations

import hmac
import os
import uuid
from typing import Any

import pyotp
import structlog
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.requests import Request
from starlette.responses import RedirectResponse, Response
from starlette.routing import Route
from starlette.status import HTTP_303_SEE_OTHER, HTTP_400_BAD_REQUEST
from starlette.templating import Jinja2Templates
from starlette_admin.auth import AdminUser, AuthProvider
from starlette_admin.contrib.sqla import Admin, ModelView
from starlette_admin.events import (
    AdminEvent,
    AfterActionContext,
    AfterCreateContext,
    AfterEditContext,
    BeforeDeleteContext,
    EventContext,
)
from starlette_admin.helpers import index_url, safe_redirect_url, wrap_endpoint_with_kwargs

from app.core.db import get_sessionmaker
from app.models import StaffUser
from app.services import staff as staff_svc

log = structlog.get_logger("admin.security")

ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "")
IS_DEV = os.environ.get("ENV", "dev") in ("dev", "test")
ENROL_KEY = "enrol_staff_id"


def staff_identity(request: Request) -> tuple[uuid.UUID | None, str | None]:
    raw = request.session.get("staff_id")
    try:
        sid = uuid.UUID(str(raw)) if raw else None
    except ValueError:
        sid = None
    return sid, request.session.get("staff")


def _session(request: Request) -> AsyncSession:
    session = request.state.session
    assert isinstance(session, AsyncSession)
    return session


class StaffAuthProvider(AuthProvider):
    """Email + password + TOTP per staff account (staff_users). The env credential
    (ADMIN_USERNAME / ADMIN_PASSWORD, no TOTP) works only in dev/test while no staff account
    exists: create the first one with ``python -m app.cli staff-create``."""

    def __init__(self) -> None:
        super().__init__(allow_routes=["staff_enroll"])

    # ---- Starlette-Admin contract ----

    async def authenticate(self, request: Request) -> AdminUser | None:
        email = request.session.get("staff")
        if not email:
            return None
        sid, _ = staff_identity(request)
        if sid is not None:
            # Deactivated staff lose access on their next request.
            async with get_sessionmaker()() as db:
                staff = await db.get(StaffUser, sid)
            if staff is None or not staff.is_active or staff.totp_enrolled_at is None:
                request.session.clear()
                return None
        return AdminUser(username=str(email))

    async def logout(self, request: Request) -> Response | None:
        request.session.clear()
        return None

    def get_routes(self, templates: Jinja2Templates) -> list[Route]:
        routes = super().get_routes(templates)
        routes.append(
            Route(
                "/enroll",
                wrap_endpoint_with_kwargs(self.render_enroll, templates=templates),
                methods=["GET", "POST"],
                name="staff_enroll",
            )
        )
        return routes

    # ---- pages ----

    def _next(self, request: Request) -> str:
        fallback = index_url(request)
        return safe_redirect_url(request.query_params.get("next") or fallback, request, fallback)

    async def render_login(self, request: Request, templates: Jinja2Templates) -> Response:
        if getattr(request.state, "admin_user", None) is not None:
            return RedirectResponse(self._next(request), status_code=HTTP_303_SEE_OTHER)
        if request.method == "GET":
            return templates.TemplateResponse(request=request, name="staff_login.html")
        form = await request.form()
        email = str(form.get("username") or "").strip()
        password = str(form.get("password") or "")
        code = str(form.get("totp") or "")
        try:
            response = await self._login(request, email, password, code)
        except staff_svc.StaffError as exc:
            log.warning("admin_login_failed", email=staff_svc.normalize_email(email))
            return templates.TemplateResponse(
                request=request,
                name="staff_login.html",
                context={"error": exc.message, "email": email},
                status_code=HTTP_400_BAD_REQUEST,
            )
        return response

    async def _login(self, request: Request, email: str, password: str, code: str) -> Response:
        async with get_sessionmaker()() as db:
            if IS_DEV and await staff_svc.staff_count(db) == 0:
                return await self._env_login(request, email, password)
            result = await staff_svc.authenticate(db, email, password, code)
            if result.needs_enrolment:
                request.session.clear()
                request.session[ENROL_KEY] = str(result.staff.id)
                await db.commit()
                return RedirectResponse(
                    str(request.url_for("admin:staff_enroll")), status_code=HTTP_303_SEE_OTHER
                )
            staff_svc.audit(
                db,
                staff_id=result.staff.id,
                staff_email=result.staff.email,
                action="login",
                model="StaffUser",
                pk=result.staff.id,
            )
            await db.commit()
        request.session.clear()
        request.session.update({"staff": result.staff.email, "staff_id": str(result.staff.id)})
        log.info("admin_login", staff_id=str(result.staff.id))
        return RedirectResponse(self._next(request), status_code=HTTP_303_SEE_OTHER)

    async def _env_login(self, request: Request, username: str, password: str) -> Response:
        key = f"env:{username.lower()}"
        wait = await staff_svc.locked_for(key)
        if wait:
            raise staff_svc.StaffError("Too many failed attempts. Try again later.")
        user_ok = hmac.compare_digest(username.encode(), ADMIN_USERNAME.encode())
        pass_ok = hmac.compare_digest(password.encode(), ADMIN_PASSWORD.encode())
        if not (ADMIN_PASSWORD and user_ok and pass_ok):
            await staff_svc.record_failure(key)
            raise staff_svc.StaffError("Invalid username or password.")
        request.session.clear()
        request.session.update({"staff": f"env:{username}"})
        log.warning("admin_env_login", note="dev only; create staff with app.cli staff-create")
        return RedirectResponse(self._next(request), status_code=HTTP_303_SEE_OTHER)

    async def render_enroll(self, request: Request, templates: Jinja2Templates) -> Response:
        raw = request.session.get(ENROL_KEY)
        if not raw:
            return RedirectResponse(
                str(request.url_for("admin:login")), status_code=HTTP_303_SEE_OTHER
            )
        staff_id = uuid.UUID(str(raw))
        async with get_sessionmaker()() as db:
            staff = await db.get(StaffUser, staff_id)
            if staff is None:
                request.session.clear()
                return RedirectResponse(
                    str(request.url_for("admin:login")), status_code=HTTP_303_SEE_OTHER
                )
            if request.method == "GET":
                uri = staff_svc.reveal_enrolment_uri(staff)
                await db.commit()
                return templates.TemplateResponse(
                    request=request,
                    name="staff_enroll.html",
                    context={
                        "uri": uri,
                        "secret": pyotp.parse_uri(uri).secret if uri else None,
                        "email": staff.email,
                    },
                )
            form = await request.form()
            try:
                staff = await staff_svc.enrol(db, staff_id, str(form.get("totp") or ""))
            except staff_svc.StaffError as exc:
                await db.commit()
                return templates.TemplateResponse(
                    request=request,
                    name="staff_enroll.html",
                    context={"error": exc.message, "uri": None, "email": staff.email},
                    status_code=HTTP_400_BAD_REQUEST,
                )
            staff_svc.audit(
                db,
                staff_id=staff.id,
                staff_email=staff.email,
                action="totp_enrolled",
                model="StaffUser",
                pk=staff.id,
            )
            await db.commit()
        request.session.clear()
        request.session.update({"staff": staff.email, "staff_id": str(staff.id)})
        return RedirectResponse(index_url(request), status_code=HTTP_303_SEE_OTHER)


# ---- audit hook ------------------------------------------------------------------------------


def _model_name(ctx: EventContext, obj: Any) -> str:
    return type(obj).__name__ if obj is not None else ctx.view_key


async def _on_create(ctx: EventContext) -> None:
    assert isinstance(ctx, AfterCreateContext)
    sid, email = staff_identity(ctx.request)
    staff_svc.audit(
        _session(ctx.request),
        staff_id=sid,
        staff_email=email,
        action="create",
        model=_model_name(ctx, ctx.obj),
        pk=ctx.pk if ctx.pk is not None else getattr(ctx.obj, "id", None),
        after=staff_svc.snapshot(ctx.obj),
    )


async def _on_edit(ctx: EventContext) -> None:
    assert isinstance(ctx, AfterEditContext)
    sid, email = staff_identity(ctx.request)
    before = staff_svc.clean(ctx.old_data or {})
    after = staff_svc.snapshot(ctx.obj)
    staff_svc.audit(
        _session(ctx.request),
        staff_id=sid,
        staff_email=email,
        action="edit",
        model=_model_name(ctx, ctx.obj),
        pk=ctx.pk,
        before=before,
        after={k: v for k, v in after.items() if k in before} or after,
    )


async def _on_delete(ctx: EventContext) -> None:
    assert isinstance(ctx, BeforeDeleteContext)
    sid, email = staff_identity(ctx.request)
    staff_svc.audit(
        _session(ctx.request),
        staff_id=sid,
        staff_email=email,
        action="delete",
        model=_model_name(ctx, ctx.obj),
        pk=ctx.pk,
        before=staff_svc.snapshot(ctx.obj),
    )


async def _on_action(ctx: EventContext) -> None:
    assert isinstance(ctx, AfterActionContext)
    sid, email = staff_identity(ctx.request)
    pks: list[Any] = []
    if ctx.selection is not None:
        try:
            pks = list(await ctx.selection.pks())
        except Exception:  # a select-all over a huge table: log the action only
            pks = []
    staff_svc.audit(
        _session(ctx.request),
        staff_id=sid,
        staff_email=email,
        action=f"action:{ctx.action_name}",
        model=ctx.view_key,
        after={"pks": [str(p) for p in pks[:500]], "success": ctx.success, "error": ctx.error},
    )


def install_audit(admin: Admin) -> None:
    """One hook for every view (current and future): create, edit, delete, actions."""
    admin.events.on(AdminEvent.AFTER_CREATE, _on_create)
    admin.events.on(AdminEvent.AFTER_EDIT, _on_edit)
    admin.events.on(AdminEvent.BEFORE_DELETE, _on_delete)
    admin.events.on(AdminEvent.AFTER_ACTION, _on_action)


# ---- soft delete -----------------------------------------------------------------------------


class SoftDeleteView(ModelView):
    """Delete sets deleted_at / archived_at / removed_at / is_active=False through the same
    service code the API uses (undo window, ticket reassignment, session revocation); the
    worker's purge does the hard delete later. Never SQL DELETE."""

    async def delete(self, request: Request, pks: list[Any]) -> int | None:
        db = _session(request)
        sid, email = staff_identity(request)
        objs = await self.find_by_pks(request, pks)
        for obj in objs:
            before = staff_svc.snapshot(obj)
            await staff_svc.soft_delete(db, obj)
            staff_svc.audit(
                db,
                staff_id=sid,
                staff_email=email,
                action="soft_delete",
                model=type(obj).__name__,
                pk=getattr(obj, "id", None),
                before=before,
                after=staff_svc.snapshot(obj),
            )
        return len(objs)
