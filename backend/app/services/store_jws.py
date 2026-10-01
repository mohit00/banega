"""Signed store notifications.

- :class:`AppleJwsDecoder`: App Store Server Notifications v2 / signed transactions are JWS
  (ES256) whose ``x5c`` header carries the leaf, the Apple WWDR intermediate and the root.
  The chain must verify certificate by certificate and end in the bundled Apple Root CA - G3
  (``APPSTORE_ROOT_CERT_PATH``); the leaf and the intermediate must carry Apple's marker
  OIDs; every certificate must be valid at the notification's ``signedDate``; then the
  signature is checked with the leaf key. Nothing in the payload is trusted before that.
- :func:`verify_pubsub_oidc`: the Google-signed OIDC token Pub/Sub push attaches
  (``Authorization: Bearer``), checked against Google's JWKS, the configured audience and
  the push service account.
"""

from __future__ import annotations

import asyncio
import base64
import json
from collections.abc import Sequence
from datetime import UTC, datetime
from functools import lru_cache
from itertools import pairwise
from pathlib import Path
from typing import Any

import jwt
import structlog
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding

from app.core.config import get_settings
from app.core.errors import AppError, Unauthorized

log = structlog.get_logger(__name__)

# Apple marker extensions (as checked by Apple's app-store-server-library).
LEAF_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.11.1")
INTERMEDIATE_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.2.1")

GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")


def _invalid(reason: str) -> AppError:
    log.warning("store_jws_rejected", reason=reason)
    return AppError(
        "invalid_signature",
        "The notification signature could not be verified.",
        "Suchna ke hastakshar ki pushti nahi hui.",
        status_code=401,
        details={"reason": reason},
    )


def load_certificate(data: bytes) -> x509.Certificate:
    if b"-----BEGIN" in data:
        return x509.load_pem_x509_certificate(data)
    return x509.load_der_x509_certificate(data)


@lru_cache(maxsize=4)
def _root_from_path(path: str) -> x509.Certificate:
    return load_certificate(Path(path).read_bytes())


def _payload_unverified(token: str) -> dict[str, Any]:
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return dict(json.loads(base64.urlsafe_b64decode(part).decode("utf-8")))
    except (IndexError, ValueError, TypeError) as exc:
        raise AppError("invalid_notification", "Bad notification.", "Galat suchna.") from exc


class AppleJwsDecoder:
    """Verifies the x5c chain to Apple's root and the ES256 signature, then returns the
    payload. ``roots`` defaults to the bundled Apple Root CA - G3 (tests pass their own)."""

    verified = True

    def __init__(
        self,
        roots: Sequence[x509.Certificate] | None = None,
        *,
        bundle_id: str | None = None,
        environment: str | None = None,
        check_marker_oids: bool = True,
    ) -> None:
        s = get_settings()
        self.roots = (
            list(roots) if roots is not None else [_root_from_path(s.APPSTORE_ROOT_CERT_PATH)]
        )
        self.bundle_id = s.APPSTORE_BUNDLE_ID if bundle_id is None else bundle_id
        self.environment = s.APPSTORE_ENVIRONMENT if environment is None else environment
        self.check_marker_oids = check_marker_oids

    def _chain(self, header: dict[str, Any]) -> list[x509.Certificate]:
        x5c = header.get("x5c")
        if header.get("alg") != "ES256":
            raise _invalid("alg")
        if not isinstance(x5c, list) or len(x5c) < 2:
            raise _invalid("x5c_missing")
        try:
            return [load_certificate(base64.b64decode(c)) for c in x5c]
        except (ValueError, TypeError) as exc:
            raise _invalid("x5c_malformed") from exc

    def _verify_chain(self, chain: list[x509.Certificate], at: datetime) -> None:
        # The presented root (if any) must be one of ours byte for byte; otherwise the last
        # presented certificate must be issued by one of ours.
        trusted = {r.public_bytes(Encoding.DER) for r in self.roots}
        certs = list(chain)
        if certs[-1].public_bytes(Encoding.DER) in trusted:
            anchor = certs.pop()
        else:
            found = next((r for r in self.roots if r.subject == certs[-1].issuer), None)
            if found is None:
                raise _invalid("untrusted_root")
            anchor = found
        path = [*certs, anchor]
        for child, parent in pairwise(path):
            try:
                child.verify_directly_issued_by(parent)
            except (ValueError, TypeError, InvalidSignature) as exc:
                raise _invalid("chain_signature") from exc
        for cert in path:
            if not (cert.not_valid_before_utc <= at <= cert.not_valid_after_utc):
                raise _invalid("certificate_expired")
        if self.check_marker_oids:
            leaf_oids = {e.oid for e in certs[0].extensions}
            if LEAF_OID not in leaf_oids:
                raise _invalid("leaf_oid")
            if len(certs) > 1 and INTERMEDIATE_OID not in {e.oid for e in certs[1].extensions}:
                raise _invalid("intermediate_oid")

    def decode(self, token: str) -> dict[str, Any]:
        try:
            header = jwt.get_unverified_header(token)
        except jwt.PyJWTError as exc:
            raise _invalid("header") from exc
        chain = self._chain(header)
        unverified = _payload_unverified(token)
        signed_ms = unverified.get("signedDate")
        try:
            at = datetime.fromtimestamp(int(signed_ms) / 1000, tz=UTC) if signed_ms else None
        except (TypeError, ValueError):
            at = None
        self._verify_chain(chain, at or datetime.now(UTC))
        key = chain[0].public_key()
        if not isinstance(key, ec.EllipticCurvePublicKey):
            raise _invalid("leaf_key")
        try:
            payload = jwt.decode(
                token,
                key=key,
                algorithms=["ES256"],
                options={"verify_aud": False, "verify_exp": False, "verify_iat": False},
            )
        except jwt.PyJWTError as exc:
            raise _invalid("signature") from exc
        self._check_app(payload)
        return dict(payload)

    def _check_app(self, payload: dict[str, Any]) -> None:
        """Notifications carry bundleId/environment under ``data``; transactions at the top."""
        data = payload.get("data")
        scope: dict[str, Any] = data if isinstance(data, dict) else payload
        bundle = scope.get("bundleId")
        env = scope.get("environment")
        if self.bundle_id and bundle is not None and bundle != self.bundle_id:
            raise _invalid("bundle_id")
        if self.environment and env is not None and env != self.environment:
            raise _invalid("environment")


# ---- Google Pub/Sub push OIDC -------------------------------------------------------------------


class _JwksClient:
    """Thin wrapper so tests can swap the key source."""

    def __init__(self, url: str = GOOGLE_JWKS_URL) -> None:
        self._client = jwt.PyJWKClient(url, cache_keys=True, lifespan=3600)

    def signing_key(self, token: str) -> Any:
        return self._client.get_signing_key_from_jwt(token).key


_jwks: Any = None


def set_jwks_client(client: Any) -> None:
    global _jwks
    _jwks = client


def _get_jwks() -> Any:
    global _jwks
    if _jwks is None:
        _jwks = _JwksClient()
    return _jwks


async def verify_pubsub_oidc(authorization: str | None) -> dict[str, Any]:
    """Validates the Pub/Sub push bearer token; returns its claims or raises 401."""
    s = get_settings()
    if not authorization or not authorization.lower().startswith("bearer "):
        raise Unauthorized("invalid_webhook_token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        key = await asyncio.to_thread(_get_jwks().signing_key, token)
        claims = jwt.decode(
            token,
            key=key,
            algorithms=["RS256"],
            audience=s.PLAY_PUBSUB_AUDIENCE,
            options={"require": ["exp", "iat", "iss", "aud"]},
        )
    except (jwt.PyJWTError, OSError) as exc:
        raise Unauthorized("invalid_webhook_token") from exc
    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise Unauthorized("invalid_webhook_token")
    if claims.get("email") != s.PLAY_PUBSUB_SERVICE_ACCOUNT or not claims.get("email_verified"):
        raise Unauthorized("invalid_webhook_token")
    return dict(claims)
