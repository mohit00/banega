"""Banega staff admin panel (Starlette-Admin) on the same models and database as the API.

Run: ``uvicorn main:app --port 8001`` from admin/ with backend/ importable (installed or on
PYTHONPATH). Served under /admin (nginx routes /admin here). Catalogue views (Phase 2) live
in ``catalogue_admin.py``; menus, tickets, duty log, inbox and the Ticket board (Phase 5) in
``kitchen_admin.py``; stock, ration, approvals, ratings, subscriptions, consents and the
Kitchen health page (Phases 6-7) in ``pantry_admin.py``; uploaded photos go to MEDIA_DIR,
served by nginx at /media.

Security (``security.py``): per-staff accounts (email + argon2id password + TOTP, lockout
after 5 failures for 15 minutes), an audit-log row for every create / edit / delete / action,
and soft deletes for users, households, members, cooks and ingredients. The env credential
(ADMIN_USERNAME / ADMIN_PASSWORD) only works in dev/test while no staff account exists.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, ClassVar

from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.sessions import SessionMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, RedirectResponse
from starlette.routing import Route
from starlette_admin import EmailField, PasswordField
from starlette_admin.actions import action
from starlette_admin.contrib.sqla import Admin, ModelView
from starlette_admin.exceptions import ActionFailed, FormValidationError

from app.core.db import get_engine
from app.models import AuditLog, Cook, Household, Invite, Member, StaffUser, Subscription, User
from app.services import staff as staff_svc
from catalogue_admin import register_catalogue_views
from kitchen_admin import register_kitchen_views
from pantry_admin import SubscriptionView, register_pantry_views
from security import SoftDeleteView, StaffAuthProvider, install_audit, staff_identity

ADMIN_SECRET_KEY = os.environ.get("ADMIN_SECRET_KEY", "")
BASE_URL = os.environ.get("ADMIN_BASE_URL", "/admin")
IS_DEV = os.environ.get("ENV", "dev") in ("dev", "test")
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"


RO_EDIT: list[Any] = ["id", "created_at"]


class _NoCreate(SoftDeleteView):
    """Accounts, households, members and cooks are created in the app (invariants: one
    household per phone, one hired cook, ...). The admin edits and soft-deletes."""

    def can_create(self, request: Request) -> bool:
        return False


class UserView(_NoCreate):
    fields: ClassVar[list[Any]] = ["id", "phone", "name", "locale", "created_at", "deleted_at"]
    searchable_fields: ClassVar[list[Any]] = ["phone", "name"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "name", "phone"]
    exclude_fields_from_create: ClassVar[list[Any]] = RO_EDIT
    exclude_fields_from_edit: ClassVar[list[Any]] = RO_EDIT


class HouseholdView(_NoCreate):
    fields: ClassVar[list[Any]] = [
        "id",
        "name",
        "timezone",
        "default_servings",
        "enabled_slots",
        "slot_defaults",
        "cook_can_approve_swaps",
        "members_can_send_to_cook",
        "show_names_to_cook",
        "auto_decrement",
        "ratings_enabled",
        "eater_defaults",
        "created_at",
        "deleted_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = [
        "slot_defaults",
        "enabled_slots",
        "eater_defaults",
    ]
    searchable_fields: ClassVar[list[Any]] = ["name", "timezone"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "name"]
    exclude_fields_from_create: ClassVar[list[Any]] = RO_EDIT
    exclude_fields_from_edit: ClassVar[list[Any]] = RO_EDIT


class MemberView(_NoCreate):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "name",
        "is_kid",
        "diet",
        "spice",
        "no_dairy",
        "nonveg_exclusions",
        "needs",
        "cuisines",
        "allergens",
        "allergens_other",
        "dislikes",
        "vrat_days",
        "show_on_home",
        "colour",
        "archived_at",
        "created_at",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = [
        "nonveg_exclusions",
        "cuisines",
        "dislikes",
        "colour",
    ]
    searchable_fields: ClassVar[list[Any]] = ["name"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "name"]
    exclude_fields_from_create: ClassVar[list[Any]] = RO_EDIT
    exclude_fields_from_edit: ClassVar[list[Any]] = RO_EDIT


class CookView(_NoCreate):
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "name",
        "kind",
        "login_mode",
        "user_id",
        "member_id",
        "phone",
        "is_primary",
        "is_backup",
        "on_duty",
        "off_duty_until",
        "off_duty_reason",
        "removed_at",
        "created_at",
    ]
    searchable_fields: ClassVar[list[Any]] = ["name"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "name"]
    exclude_fields_from_create: ClassVar[list[Any]] = RO_EDIT
    exclude_fields_from_edit: ClassVar[list[Any]] = RO_EDIT


class InviteView(ModelView):
    # token_hash is never shown; invites are created by household admins in the app.
    fields: ClassVar[list[Any]] = [
        "id",
        "household_id",
        "phone",
        "role",
        "member_id",
        "expires_at",
        "used_at",
        "revoked_at",
        "created_by",
        "created_at",
    ]
    searchable_fields: ClassVar[list[Any]] = ["phone"]
    sortable_fields: ClassVar[list[Any]] = ["created_at", "expires_at"]

    def can_create(self, request: Request) -> bool:
        return False

    def can_edit(self, request: Request) -> bool:
        return False


class StaffUserView(ModelView):
    """Staff accounts. Create sets the password (argon2id) and a TOTP secret; the new staff
    member sees the otpauth URI once on first login. Deactivate instead of delete."""

    fields: ClassVar[list[Any]] = [
        "id",
        EmailField("email", required=True),
        PasswordField(
            "password",
            label="Password (12+ characters)",
            exclude_from_list=True,
            exclude_from_detail=True,
            exclude_from_edit=True,
        ),
        "is_active",
        "totp_enrolled_at",
        "last_login",
        "created_at",
    ]
    exclude_fields_from_create: ClassVar[list[Any]] = [
        "id",
        "is_active",
        "totp_enrolled_at",
        "last_login",
        "created_at",
    ]
    exclude_fields_from_edit: ClassVar[list[Any]] = [
        "id",
        "email",
        "totp_enrolled_at",
        "last_login",
        "created_at",
    ]
    searchable_fields: ClassVar[list[Any]] = ["email"]
    sortable_fields: ClassVar[list[Any]] = ["email", "created_at", "last_login"]

    def can_delete(self, request: Request) -> bool:
        return False

    async def create(self, request: Request, data: dict[str, Any]) -> Any:
        db = request.state.session
        try:
            staff = await staff_svc.create_staff(
                db, str(data.get("email") or ""), str(data.get("password") or "")
            )
        except ValueError as exc:
            return await self.handle_exception(request, FormValidationError({"password": str(exc)}))
        sid, email = staff_identity(request)
        staff_svc.audit(
            db,
            staff_id=sid,
            staff_email=email,
            action="create",
            model="StaffUser",
            pk=staff.id,
            after=staff_svc.snapshot(staff),
        )
        return staff

    @action(
        name="reset_totp",
        text="Reset authenticator",
        confirmation="New TOTP secret? The staff member enrols again on the next login.",
    )
    async def reset_totp_action(self, request: Request, selection: Any) -> str:
        db = request.state.session
        rows = await self.find_by_pks(request, list(await selection.pks()))
        if not rows:
            raise ActionFailed("Nothing selected.")
        for staff in rows:
            staff_svc.reset_totp(staff)
        await db.flush()
        return f"{len(rows)} authenticator(s) reset."


class AuditLogView(ModelView):
    fields: ClassVar[list[Any]] = [
        "id",
        "at",
        "staff_email",
        "action",
        "model",
        "pk",
        "before",
        "after",
        "staff_id",
    ]
    exclude_fields_from_list: ClassVar[list[Any]] = ["before", "after", "staff_id"]
    searchable_fields: ClassVar[list[Any]] = ["staff_email", "action", "model", "pk"]
    sortable_fields: ClassVar[list[Any]] = ["at", "model", "action"]

    def can_create(self, request: Request) -> bool:
        return False

    def can_edit(self, request: Request) -> bool:
        return False

    def can_delete(self, request: Request) -> bool:
        return False


async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


async def root(_: Request) -> RedirectResponse:
    return RedirectResponse(f"{BASE_URL}/")


def create_app() -> Starlette:
    if not ADMIN_SECRET_KEY and not IS_DEV:
        raise RuntimeError("ADMIN_SECRET_KEY must be set outside dev")
    secret = ADMIN_SECRET_KEY or "dev-admin-secret-change-me"
    app = Starlette(routes=[Route("/healthz", health), Route("/", root)])
    admin = Admin(
        get_engine(),
        title="Banega Admin",
        base_url=BASE_URL,
        templates_dir=str(TEMPLATES_DIR),
        auth_provider=StaffAuthProvider(),
        secret_key=secret,
        middlewares=[
            Middleware(
                SessionMiddleware,
                secret_key=secret,
                session_cookie="banega_admin",
                https_only=not IS_DEV,
                same_site="strict",
                max_age=8 * 3600,
            )
        ],
    )
    admin.add_view(UserView(User, icon="fa fa-user"))
    admin.add_view(HouseholdView(Household, icon="fa fa-house"))
    admin.add_view(MemberView(Member, icon="fa fa-people-group"))
    admin.add_view(CookView(Cook, icon="fa fa-kitchen-set"))
    admin.add_view(InviteView(Invite, icon="fa fa-envelope"))
    admin.add_view(SubscriptionView(Subscription, icon="fa fa-credit-card"))
    register_catalogue_views(admin)
    register_kitchen_views(admin)
    register_pantry_views(admin)
    admin.add_view(StaffUserView(StaffUser, icon="fa fa-user-shield"))
    admin.add_view(AuditLogView(AuditLog, icon="fa fa-clipboard-list"))
    install_audit(admin)
    admin.mount_to(app)
    return app


app = create_app()
