"""Household, memberships (roles), member profiles, cooks, invites and subscriptions."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    Boolean,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    false,
    text,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import (
    Base,
    JSONType,
    SoftDelete,
    Timestamped,
    UTCDateTime,
    UUIDPk,
    str_enum,
)
from app.models.enums import (
    CookKind,
    CookLoginMode,
    Diet,
    InviteRole,
    MembershipStatus,
    Spice,
    SubscriptionStatus,
)

DEFAULT_SLOTS = ["nashta", "lunch", "dinner"]


def _default_slots() -> list[str]:
    return list(DEFAULT_SLOTS)


class Household(UUIDPk, Timestamped, SoftDelete, Base):
    __tablename__ = "households"

    name: Mapped[str] = mapped_column(String(80), nullable=False)
    timezone: Mapped[str] = mapped_column(
        String(64), default="Asia/Kolkata", server_default="Asia/Kolkata"
    )
    default_servings: Mapped[int] = mapped_column(Integer, default=4, server_default="4")
    enabled_slots: Mapped[list[str]] = mapped_column(JSONType, default=_default_slots)
    # {"nashta": {"due": "08:30"}, "lunch": {...}}
    slot_defaults: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    cook_can_approve_swaps: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default=true()
    )
    members_can_send_to_cook: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default=true()
    )
    # F-5.10-01: the hired cook sees ratings without names unless the admin turns this on.
    show_names_to_cook: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    # F-5.6-01: remembered eaters per "slot:weekday" (weekday 0 = Monday) -> [member_id].
    eater_defaults: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    # FR-S4 (Should, F-5.8-02): on Completed, perishable tracked items drop in -> low once.
    auto_decrement: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    # F-5.10-04: a family cook may turn ratings off (appreciation-first); 409 ratings_disabled.
    ratings_enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())

    def __str__(self) -> str:
        return self.name


class Member(UUIDPk, Timestamped, Base):
    """A food profile: somebody who eats. May or may not have a login (User)."""

    __tablename__ = "members"

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    colour: Mapped[str | None] = mapped_column(String(16))
    is_kid: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    diet: Mapped[Diet] = mapped_column(str_enum(Diet, "diet"), default=Diet.veg, nullable=False)
    nonveg_exclusions: Mapped[list[str]] = mapped_column(JSONType, default=list)
    no_dairy: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    spice: Mapped[Spice] = mapped_column(
        str_enum(Spice, "spice"), default=Spice.medium, nullable=False
    )
    needs: Mapped[list[str]] = mapped_column(JSONType, default=list)
    cuisines: Mapped[list[str]] = mapped_column(JSONType, default=list)
    # Allergen picklist values only (F-5.2-03): the engine's hard No.
    allergens: Mapped[list[str]] = mapped_column(JSONType, default=list)
    # Free text the picklist does not cover: shown as a warning, never a hard No.
    allergens_other: Mapped[str | None] = mapped_column(String(200))
    dislikes: Mapped[list[str]] = mapped_column(JSONType, default=list)
    # Fasting weekdays (0 = Monday .. 6 = Sunday): the engine's vrat rule applies on them.
    vrat_days: Mapped[list[int]] = mapped_column(
        JSONType, default=list, server_default=text("'[]'")
    )
    # F-5.3-05: health needs appear in the constraint line only for members who chose it.
    show_on_home: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    archived_at: Mapped[datetime | None] = mapped_column(UTCDateTime())

    def __str__(self) -> str:
        return self.name


class Cook(UUIDPk, Timestamped, Base):
    __tablename__ = "cooks"
    __table_args__ = (
        # F-2-05: one active hired cook per household.
        Index(
            "uq_cooks_one_hired_per_household",
            "household_id",
            unique=True,
            postgresql_where=text("kind = 'hired' AND removed_at IS NULL"),
            sqlite_where=text("kind = 'hired' AND removed_at IS NULL"),
        ),
        # One active cook row per phone within a household. Across households (FR-K20) the
        # rule stays in services.cooks.check_phone_free, which ignores soft-deleted homes.
        Index(
            "uq_cooks_active_phone_per_household",
            "household_id",
            "phone",
            unique=True,
            postgresql_where=text("phone IS NOT NULL AND removed_at IS NULL"),
            sqlite_where=text("phone IS NOT NULL AND removed_at IS NULL"),
        ),
    )

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    kind: Mapped[CookKind] = mapped_column(str_enum(CookKind, "cook_kind"), nullable=False)
    name: Mapped[str | None] = mapped_column(String(80))
    member_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("members.id", ondelete="SET NULL"), index=True
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    login_mode: Mapped[CookLoginMode] = mapped_column(
        str_enum(CookLoginMode, "cook_login_mode"), default=CookLoginMode.own, nullable=False
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    is_backup: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    on_duty: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    # F-5.7-06: end of the current off-duty period (None = until toggled back on).
    off_duty_until: Mapped[datetime | None] = mapped_column(UTCDateTime())
    off_duty_reason: Mapped[str | None] = mapped_column(String(40))
    # Hired cooks are added by phone (FR-K20: one household per hired-cook phone in v1).
    phone: Mapped[str | None] = mapped_column(String(20), index=True)
    # Removing a cook keeps the row (history keeps the name, F-5.7-10) but drops the role.
    removed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())

    def __str__(self) -> str:
        return self.name or f"Cook {self.id}"


class HouseholdMembership(UUIDPk, Timestamped, Base):
    """Replaces User.role (F-8-01): one user can be admin, member and cook in one household."""

    __tablename__ = "household_memberships"
    __table_args__ = (
        UniqueConstraint("user_id", "household_id"),
        # v1 (F-2-06 / FR-K20): one active household per login. Memberships in soft-deleted
        # households are released (status removed) when the user creates / joins another.
        Index(
            "uq_household_memberships_active_user",
            "user_id",
            unique=True,
            postgresql_where=text("status = 'active'"),
            sqlite_where=text("status = 'active'"),
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    is_member: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    member_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("members.id", ondelete="SET NULL"), index=True
    )
    cook_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("cooks.id", ondelete="SET NULL"), index=True
    )
    status: Mapped[MembershipStatus] = mapped_column(
        str_enum(MembershipStatus, "membership_status"),
        default=MembershipStatus.active,
        nullable=False,
    )


class Invite(UUIDPk, Timestamped, Base):
    __tablename__ = "invites"

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    role: Mapped[InviteRole] = mapped_column(str_enum(InviteRole, "invite_role"), nullable=False)
    # Optional: link the invitee to an existing profile (e.g. "Papa" already added by the admin).
    member_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("members.id", ondelete="SET NULL"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )


class Subscription(UUIDPk, Timestamped, Base):
    __tablename__ = "subscriptions"

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    status: Mapped[SubscriptionStatus] = mapped_column(
        str_enum(SubscriptionStatus, "subscription_status"),
        default=SubscriptionStatus.trial,
        nullable=False,
    )
    product_id: Mapped[str | None] = mapped_column(String(128))
    trial_ends_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    renews_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    # play | app_store
    store: Mapped[str | None] = mapped_column(String(32))
    # F-3-03: billing retry keeps full access until grace_until (renews_at + 3 days).
    grace_until: Mapped[datetime | None] = mapped_column(UTCDateTime())
    # App Store originalTransactionId / Play purchaseToken: webhooks find the row by these.
    # Unique: one purchase belongs to one household (NULLs allowed many times).
    original_transaction_id: Mapped[str | None] = mapped_column(
        String(128), index=True, unique=True
    )
    purchase_token: Mapped[str | None] = mapped_column(String(512), index=True, unique=True)
    last_event_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    # One server-side trial per phone number and device id (F-3-03).
    trial_phone: Mapped[str | None] = mapped_column(String(20), index=True)
    trial_device_id: Mapped[str | None] = mapped_column(String(128), index=True)
