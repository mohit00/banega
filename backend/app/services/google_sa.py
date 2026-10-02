"""Google service-account credentials (FCM HTTP v1, Play Developer API).

The key is read from ``*_SERVICE_ACCOUNT_FILE`` (a path, mounted read-only) or
``*_SERVICE_ACCOUNT_JSON`` (the JSON itself). :class:`GoogleTokenSource` mints OAuth2 access
tokens with google-auth (a signed JWT exchanged at Google's token endpoint) and caches them
until a minute before expiry. google-auth's transport is synchronous, so the refresh runs in
a thread. Tests swap in any object with ``async def token() -> str``.
"""

from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Protocol

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher"


class ServiceAccountError(RuntimeError):
    pass


class TokenSource(Protocol):
    async def token(self) -> str: ...


def load_service_account(file: str, raw: str, name: str) -> dict[str, Any]:
    """The key as a dict; ``name`` (e.g. "FCM") only labels the error."""
    try:
        if file:
            info = json.loads(Path(file).read_text(encoding="utf-8"))
        elif raw:
            info = json.loads(raw)
        else:
            raise ServiceAccountError(f"{name}_SERVICE_ACCOUNT_FILE / _JSON is not set")
    except (OSError, ValueError) as exc:
        raise ServiceAccountError(f"{name} service account key unreadable") from exc
    if not isinstance(info, dict) or not info.get("client_email"):
        raise ServiceAccountError(f"{name} service account key is not a service-account JSON")
    return info


class GoogleTokenSource:
    def __init__(self, info: dict[str, Any], scopes: list[str]) -> None:
        from google.oauth2 import service_account

        self._creds = service_account.Credentials.from_service_account_info(  # type: ignore[no-untyped-call]
            info, scopes=scopes
        )
        self._lock = asyncio.Lock()
        self._token: str | None = None
        self._expires: datetime | None = None

    def _refresh(self) -> tuple[str, datetime | None]:
        from google.auth.transport.requests import Request

        self._creds.refresh(Request())
        expiry = self._creds.expiry
        # google-auth reports a naive UTC datetime.
        if expiry is not None and expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=UTC)
        return str(self._creds.token), expiry

    async def token(self) -> str:
        async with self._lock:
            now = datetime.now(UTC)
            if self._token and self._expires and now < self._expires - timedelta(seconds=60):
                return self._token
            token, self._expires = await asyncio.to_thread(self._refresh)
            self._token = token
            return token
