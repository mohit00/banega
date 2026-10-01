"""Subscription, store webhooks, consent and data export (contract Phase 7)."""

from __future__ import annotations

import asyncio
import hmac
import os
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Body, Header, status
from fastapi.responses import FileResponse
from sqlalchemy import select

from app.api.deps import DB, Auth, HouseholdCtx, active_membership
from app.core.config import get_settings
from app.core.errors import AppError, NotFound, Unauthorized
from app.core.security import utcnow
from app.models import Consent, ExportJob, ExportStatus
from app.permissions import Action
from app.schemas_pantry import (
    ConsentIn,
    ConsentOut,
    ExportJobOut,
    RestoreIn,
    SubscriptionStateOut,
)
from app.services import export as export_svc
from app.services import subscription as sub_svc
from app.services.store_jws import verify_pubsub_oidc

router = APIRouter(tags=["billing"])


# ---- subscription --------------------------------------------------------------------------


@router.get("/subscription", response_model=SubscriptionStateOut)
async def get_subscription(ctx: HouseholdCtx, db: DB) -> SubscriptionStateOut:
    sub = await sub_svc.for_household(db, ctx.household.id)
    return SubscriptionStateOut.model_validate(sub_svc.view(sub, utcnow()))


@router.post("/subscription/restore", response_model=SubscriptionStateOut)
async def restore_subscription(body: RestoreIn, ctx: HouseholdCtx, db: DB) -> SubscriptionStateOut:
    """Restore purchases (the admin's store account): verified by the store adapter."""
    ctx.require(Action.edit_household)
    sub = await sub_svc.restore(
        db,
        ctx.household,
        store=body.store,
        receipt=body.receipt,
        purchase_token=body.purchase_token,
        product_id=body.product_id,
    )
    await db.commit()
    return SubscriptionStateOut.model_validate(sub_svc.view(sub, utcnow()))


async def _check_play_auth(secret_header: str | None, authorization: str | None) -> None:
    """Header secret (never a query string: it would land in access logs) or the Pub/Sub
    push OIDC token. Nothing configured: open in dev/test only."""
    s = get_settings()
    secret = s.PLAY_WEBHOOK_SECRET
    oidc = bool(s.PLAY_PUBSUB_AUDIENCE and s.PLAY_PUBSUB_SERVICE_ACCOUNT)
    if secret and secret_header:
        if not hmac.compare_digest(secret_header.encode(), secret.encode()):
            raise Unauthorized("invalid_webhook_secret")
        return
    if oidc and authorization:
        await verify_pubsub_oidc(authorization)
        return
    if not secret and not oidc and s.is_dev:
        return
    raise Unauthorized("invalid_webhook_secret" if secret else "webhook_secret_missing")


@router.post("/webhooks/play", tags=["webhooks"])
async def play_webhook(
    db: DB,
    body: Annotated[dict[str, Any], Body()],
    x_webhook_secret: Annotated[str | None, Header()] = None,
    authorization: Annotated[str | None, Header()] = None,
) -> dict[str, str]:
    """Google Play RTDN (Pub/Sub push). Always 200 for well-formed messages so Pub/Sub does
    not retry unknown tokens forever."""
    await _check_play_auth(x_webhook_secret, authorization)
    result = await sub_svc.handle_play(db, body)
    await db.commit()
    return {"result": result}


@router.post("/webhooks/appstore", tags=["webhooks"])
async def appstore_webhook(db: DB, body: Annotated[dict[str, Any], Body()]) -> dict[str, str]:
    """App Store Server Notifications v2 (``{signedPayload}``); the JWS is the credential."""
    result = await sub_svc.handle_appstore(db, body)
    await db.commit()
    return {"result": result}


# ---- consent -----------------------------------------------------------------------------------


async def consent_state(db: DB, user_id: uuid.UUID) -> ConsentOut:
    current = get_settings().CONSENT_VERSION
    row = (
        await db.execute(
            select(Consent)
            .where(Consent.user_id == user_id)
            .order_by(Consent.accepted_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    has_current = (
        await db.execute(
            select(Consent.id).where(Consent.user_id == user_id, Consent.version == current)
        )
    ).first() is not None
    return ConsentOut(
        version=row.version if row else None,
        accepted_at=row.accepted_at if row else None,
        current_version=current,
        required=not has_current,
    )


@router.post("/consent", response_model=ConsentOut)
async def post_consent(body: ConsentIn, auth: Auth, db: DB) -> ConsentOut:
    """DPDP consent (F-X-02, FR-A9): the first-run screen (``consent_title``,
    ``consent_body``, ``consent_llm_note``) posts the version it showed. Idempotent."""
    current = get_settings().CONSENT_VERSION
    if body.version != current:
        raise AppError(
            "unknown_consent_version",
            "Please accept the current privacy notice.",
            "Kripya nayi privacy suchna sweekar kijiye.",
            status_code=422,
            details={"current_version": current},
        )
    exists = (
        await db.execute(
            select(Consent).where(Consent.user_id == auth.user.id, Consent.version == body.version)
        )
    ).scalar_one_or_none()
    if exists is None:
        membership = await active_membership(db, auth.user.id)
        db.add(
            Consent(
                user_id=auth.user.id,
                household_id=membership.household_id if membership else None,
                version=body.version,
                accepted_at=utcnow(),
            )
        )
        await db.commit()
    return await consent_state(db, auth.user.id)


@router.get("/consent", response_model=ConsentOut)
async def get_consent(auth: Auth, db: DB) -> ConsentOut:
    return await consent_state(db, auth.user.id)


# ---- export ------------------------------------------------------------------------------------


def _job_out(job: ExportJob) -> ExportJobOut:
    return ExportJobOut(
        id=job.id,
        status=job.status.value,
        created_at=job.created_at,
        finished_at=job.finished_at,
        download_url=export_svc.download_path(job) if job.status == ExportStatus.done else None,
    )


@router.post("/export", response_model=ExportJobOut, status_code=status.HTTP_202_ACCEPTED)
async def request_export(ctx: HouseholdCtx, db: DB) -> ExportJobOut:
    """Queues a JSON export of the household; an inbox item carries the link when ready.
    One pending job per household: asking again while it runs returns the same job."""
    ctx.require(Action.edit_household)
    pending = (
        await db.execute(
            select(ExportJob).where(
                ExportJob.household_id == ctx.household.id,
                ExportJob.status == ExportStatus.pending,
            )
        )
    ).scalar_one_or_none()
    if pending is not None:
        return _job_out(pending)
    job = ExportJob(household_id=ctx.household.id, requested_by=ctx.user.id, created_at=utcnow())
    db.add(job)
    await db.commit()
    if not await export_svc.enqueue(job.id):
        await export_svc.run(db, job.id)
        await db.commit()
    await db.refresh(job)
    return _job_out(job)


async def _job(db: DB, ctx: HouseholdCtx, job_id: uuid.UUID) -> ExportJob:
    ctx.require(Action.edit_household)
    job = await db.get(ExportJob, job_id)
    if job is None or job.household_id != ctx.household.id:
        raise NotFound()
    return job


@router.get("/export/{job_id}", response_model=ExportJobOut)
async def export_status(job_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> ExportJobOut:
    return _job_out(await _job(db, ctx, job_id))


@router.get("/export/{job_id}/download", response_model=None)
async def export_download(job_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> FileResponse:
    job = await _job(db, ctx, job_id)
    ready = job.status == ExportStatus.done and bool(job.file_path)
    if not ready or not await asyncio.to_thread(os.path.exists, str(job.file_path)):
        raise NotFound("export_not_ready")
    return FileResponse(
        str(job.file_path), media_type="application/json", filename=f"banega-export-{job.id}.json"
    )
