"""Invites bound to a phone number, single-use, 7-day expiry, revocable (F-5.1-02)."""

from __future__ import annotations

import re
import secrets
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, status
from sqlalchemy import ColumnElement, select, update

from app.api.deps import DB, Auth, AuthContext, HouseholdCtx, active_membership
from app.core.config import get_settings
from app.core.errors import Conflict, Forbidden, Gone, NotFound, TooManyRequests
from app.core.kv import get_kv
from app.core.security import hmac_hash, hmac_hash_candidates, new_url_token, utcnow
from app.models import (
    Cook,
    CookKind,
    CookLoginMode,
    Household,
    HouseholdMembership,
    Invite,
    InviteRole,
    Member,
    MembershipStatus,
)
from app.permissions import Action
from app.schemas import (
    InviteCodeIn,
    InviteCreatedOut,
    InviteIn,
    InviteOut,
    MembershipOut,
    MeOut,
    UserOut,
)
from app.services.cooks import check_hired_limit, check_phone_free
from app.services.membership import release_deleted_memberships

router = APIRouter(prefix="/invites", tags=["invites"])


async def _household_cook_by_phone(db: DB, household_id: uuid.UUID, phone: str) -> Cook | None:
    """A hired cook the admin already added by phone (POST /cooks) and not yet linked."""
    stmt = select(Cook).where(
        Cook.household_id == household_id,
        Cook.phone == phone,
        Cook.kind == CookKind.hired,
        Cook.removed_at.is_(None),
    )
    return (await db.execute(stmt.limit(1))).scalar_one_or_none()


async def _has_primary(db: DB, household_id: uuid.UUID) -> bool:
    stmt = select(Cook.id).where(
        Cook.household_id == household_id, Cook.is_primary.is_(True), Cook.removed_at.is_(None)
    )
    return (await db.execute(stmt.limit(1))).first() is not None


def _pending() -> list[ColumnElement[bool]]:
    now = utcnow()
    return [Invite.used_at.is_(None), Invite.revoked_at.is_(None), Invite.expires_at > now]


# No 0/O/1/I: the code is read out over the phone and typed on a small keyboard.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6
# Wrong codes per user per hour before accept-code locks (the code space is 32^6 and every
# invite is also bound to the invitee's phone; this only stops scripted guessing).
CODE_MAX_WRONG_PER_HOUR = 10


def normalise_code(raw: str) -> str:
    return re.sub(r"[\s\-_.]", "", raw).upper()


def _code_hash(code: str) -> str:
    return hmac_hash(f"invite-code:{code}", "invite")


async def _new_code(db: DB) -> tuple[str, str]:
    """A code no pending invite uses (any household)."""
    for _ in range(10):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        digest = _code_hash(code)
        taken = await db.execute(
            select(Invite.id).where(Invite.code_hash == digest, *_pending()).limit(1)
        )
        if taken.first() is None:
            return code, digest
    raise Conflict("invite_code_exhausted")  # pragma: no cover - 1e9 codes


def share_text(household: str, inviter: str | None, code: str, link: str, expires: datetime) -> str:
    """WhatsApp-ready invite message: Hinglish first, then English, then the link."""
    days = max(1, round((expires - utcnow()).total_seconds() / 86400))
    who_hi = f"{inviter} ne aapko" if inviter else "Aapko"
    who_en = f"{inviter} invited you" if inviter else "You're invited"
    return (
        f'Namaste! {who_hi} Banega par "{household}" ghar mein joda hai. '
        f'Banega app kholiye, isi number se login kijiye aur "Code se judiye" mein ye code '
        f"daaliye: {code} ({days} din tak chalega).\n\n"
        f'Hi! {who_en} to the "{household}" family on Banega. Open the Banega app, log in '
        f'with this phone number and choose "Join my family with a code": {code} '
        f"(valid for {days} days).\n{link}"
    )


@router.post("", response_model=InviteCreatedOut, status_code=status.HTTP_201_CREATED)
async def create_invite(body: InviteIn, ctx: HouseholdCtx, db: DB) -> InviteCreatedOut:
    ctx.require(Action.manage_members)
    if body.member_id is not None:
        member = await db.get(Member, body.member_id)
        if member is None or member.household_id != ctx.household.id:
            raise NotFound()
    if (
        body.role == InviteRole.cook
        and await _household_cook_by_phone(db, ctx.household.id, body.phone) is None
    ):
        # F-2-05 / FR-K20: one hired cook per household; the phone is not a cook elsewhere.
        await check_hired_limit(db, ctx.household.id)
        await check_phone_free(db, ctx.household.id, body.phone)
    now = utcnow()
    # A new invite to the same number supersedes any pending one.
    await db.execute(
        update(Invite)
        .where(Invite.household_id == ctx.household.id, Invite.phone == body.phone, *_pending())
        .values(revoked_at=now)
    )
    token = new_url_token()
    code, code_hash = await _new_code(db)
    invite = Invite(
        household_id=ctx.household.id,
        phone=body.phone,
        role=body.role,
        member_id=body.member_id,
        token_hash=hmac_hash(f"invite:{token}", "invite"),
        code_hash=code_hash,
        expires_at=now + timedelta(days=get_settings().INVITE_TTL_DAYS),
        created_by=ctx.user.id,
    )
    db.add(invite)
    await db.commit()
    await db.refresh(invite)
    base = InviteOut.model_validate(invite).model_dump()
    link = f"{get_settings().INVITE_LINK_BASE}{token}"
    return InviteCreatedOut(
        **base,
        token=token,
        link=link,
        code=code,
        share_text=share_text(ctx.household.name, ctx.user.name, code, link, invite.expires_at),
    )


@router.get("", response_model=list[InviteOut])
async def list_invites(ctx: HouseholdCtx, db: DB) -> list[InviteOut]:
    ctx.require(Action.manage_members)
    rows = await db.execute(
        select(Invite)
        .where(Invite.household_id == ctx.household.id, *_pending())
        .order_by(Invite.created_at.desc())
    )
    return [InviteOut.model_validate(i) for i in rows.scalars()]


@router.delete("/{invite_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_invite(invite_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> None:
    ctx.require(Action.manage_members)
    invite = await db.get(Invite, invite_id)
    if invite is None or invite.household_id != ctx.household.id:
        raise NotFound()
    if invite.revoked_at is None and invite.used_at is None:
        invite.revoked_at = utcnow()
        await db.commit()


_EXPIRED = Gone(
    "invite_expired",
    "This invite has expired. Ask the admin for a new one.",
    "Invite purana ho gaya — admin se naya maangiye.",
)


@router.post("/accept-code", response_model=MeOut)
async def accept_invite_code(body: InviteCodeIn, auth: Auth, db: DB) -> MeOut:
    """Join with the short code from the admin's WhatsApp message (same rules as the link)."""
    kv = get_kv()
    wrong_key = f"invite:code:wrong:{auth.user.id}"
    if int(await kv.get(wrong_key) or 0) >= CODE_MAX_WRONG_PER_HOUR:
        raise TooManyRequests(
            "invite_code_locked",
            "Too many wrong codes. Please try again in an hour.",
            "Bahut baar galat code. Ek ghante baad try kijiye.",
            details={"retry_after": await kv.ttl(wrong_key)},
        )
    code = normalise_code(body.code)
    rows = (
        await db.execute(
            select(Invite)
            .where(Invite.code_hash == _code_hash(code))
            .order_by(Invite.created_at.desc())
        )
    ).scalars()
    candidates = list(rows)
    now = utcnow()
    live = [
        i for i in candidates if i.used_at is None and i.revoked_at is None and i.expires_at > now
    ]
    if not candidates:
        await kv.incr(wrong_key, 3600)
        raise NotFound(
            "invite_code_invalid",
            "This code is not right. Check the message and try again.",
            "Ye code sahi nahi hai. Message dekh kar dobara daaliye.",
        )
    return await _accept(live[0] if live else candidates[0], auth, db)


@router.post("/{token}/accept", response_model=MeOut)
async def accept_invite(token: str, auth: Auth, db: DB) -> MeOut:
    """The invitee must be logged in by OTP on the same phone the admin invited."""
    invite = (
        await db.execute(
            select(Invite).where(
                Invite.token_hash.in_(hmac_hash_candidates(f"invite:{token}", "invite"))
            )
        )
    ).scalar_one_or_none()
    if invite is None:
        raise NotFound("invite_not_found")
    return await _accept(invite, auth, db)


async def _accept(invite: Invite, auth: AuthContext, db: DB) -> MeOut:
    now = utcnow()
    if invite.used_at is not None or invite.revoked_at is not None or invite.expires_at <= now:
        raise _EXPIRED
    household = await db.get(Household, invite.household_id)
    if household is None or household.deleted_at is not None:
        raise _EXPIRED
    if auth.user.phone != invite.phone:
        raise Forbidden(
            "invite_phone_mismatch",
            "This invite was sent to a different phone number.",
            "Ye invite kisi aur number ke liye hai.",
        )
    if auth.user.deleted_at is not None:
        raise Forbidden("account_pending_deletion")
    if await active_membership(db, auth.user.id) is not None:
        # FR-K20 / v1: a phone number belongs to exactly one household.
        raise Conflict(
            "already_in_household",
            "This number already belongs to a household.",
            "Ye number dusre ghar mein hai.",
        )

    if invite.role == InviteRole.cook and auth.user.phone is not None:
        # FR-K20: a hired-cook phone serves one household (as when the admin adds her).
        await check_phone_free(db, household.id, auth.user.phone)
    await release_deleted_memberships(db, auth.user.id)
    membership = (
        await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.user_id == auth.user.id,
                HouseholdMembership.household_id == household.id,
            )
        )
    ).scalar_one_or_none()
    if membership is None:
        membership = HouseholdMembership(user_id=auth.user.id, household_id=household.id)
        db.add(membership)
    membership.status = MembershipStatus.active
    membership.is_admin = False
    cook_kind: CookKind | None = None
    if invite.role == InviteRole.cook:
        cook = await _household_cook_by_phone(db, household.id, auth.user.phone)
        if cook is None:
            await check_hired_limit(db, household.id)
            cook = Cook(
                household_id=household.id,
                kind=CookKind.hired,
                name=auth.user.name,
                phone=auth.user.phone,
                is_primary=not await _has_primary(db, household.id),
            )
            db.add(cook)
            await db.flush()
        cook.user_id = auth.user.id
        cook.login_mode = CookLoginMode.own
        cook.name = cook.name or auth.user.name
        membership.cook_id = cook.id
        membership.is_member = False
        cook_kind = CookKind.hired
    else:
        membership.is_member = True
        membership.member_id = invite.member_id
        if invite.member_id is not None:
            # A profile-only family cook who now has a login cooks from her own app.
            family_cook = (
                await db.execute(
                    select(Cook).where(
                        Cook.household_id == household.id,
                        Cook.member_id == invite.member_id,
                        Cook.removed_at.is_(None),
                    )
                )
            ).scalar_one_or_none()
            if family_cook is not None:
                family_cook.user_id = auth.user.id
                family_cook.login_mode = CookLoginMode.own
                membership.cook_id = family_cook.id
                cook_kind = family_cook.kind
    invite.used_at = now
    await db.commit()
    await db.refresh(membership)
    return MeOut(
        user=UserOut.model_validate(auth.user),
        membership=MembershipOut.model_validate(membership),
        cook_kind=cook_kind,
    )
