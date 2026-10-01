"""Push token registration."""

from __future__ import annotations

import uuid

import structlog
from fastapi import APIRouter, status
from sqlalchemy import select

from app.api.deps import DB, Auth
from app.core.errors import NotFound
from app.models import Device
from app.schemas import DeviceIn, DeviceOut

router = APIRouter(prefix="/devices", tags=["devices"])
log = structlog.get_logger(__name__)


@router.post("", response_model=DeviceOut, status_code=status.HTTP_201_CREATED)
async def register_device(body: DeviceIn, auth: Auth, db: DB) -> DeviceOut:
    """Upsert by push token: a token moves to whoever registered it last."""
    device = (
        await db.execute(select(Device).where(Device.push_token == body.push_token))
    ).scalar_one_or_none()
    if device is None:
        device = Device(user_id=auth.user.id, **body.model_dump())
        db.add(device)
    else:
        if device.user_id != auth.user.id:
            # Shared phone / reinstall: the token follows the latest login. Logged so a
            # support case ("my pushes went to someone else") can be traced.
            log.info(
                "device_rebound",
                device_id=str(device.id),
                previous_user_id=str(device.user_id),
                user_id=str(auth.user.id),
            )
        device.user_id = auth.user.id
        device.platform = body.platform
        device.app_version = body.app_version
    await db.commit()
    await db.refresh(device)
    return DeviceOut.model_validate(device)


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(device_id: uuid.UUID, auth: Auth, db: DB) -> None:
    device = await db.get(Device, device_id)
    if device is None or device.user_id != auth.user.id:
        raise NotFound()
    await db.delete(device)
    await db.commit()
