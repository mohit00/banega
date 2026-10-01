"""A throwaway Apple-like PKI for App Store JWS tests: root -> intermediate -> leaf, with
Apple's marker OIDs, and an ES256 signer that puts the chain in the x5c header."""

from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding
from cryptography.x509.oid import NameOID

from app.services.store_jws import INTERMEDIATE_OID, LEAF_OID


def _name(cn: str) -> x509.Name:
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])


def _cert(
    subject: str,
    issuer: str,
    key: ec.EllipticCurvePrivateKey,
    signer: ec.EllipticCurvePrivateKey,
    *,
    ca: bool,
    marker: x509.ObjectIdentifier | None = None,
    not_after: datetime | None = None,
) -> x509.Certificate:
    now = datetime.now(UTC)
    builder = (
        x509.CertificateBuilder()
        .subject_name(_name(subject))
        .issuer_name(_name(issuer))
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(not_after or now + timedelta(days=365))
        .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True)
    )
    if marker is not None:
        builder = builder.add_extension(x509.UnrecognizedExtension(marker, b"\x05\x00"), False)
    return builder.sign(signer, hashes.SHA256())


@dataclass
class TestPki:
    root: x509.Certificate
    intermediate: x509.Certificate
    leaf: x509.Certificate
    leaf_key: ec.EllipticCurvePrivateKey

    def sign(self, payload: dict[str, Any], *, chain: list[x509.Certificate] | None = None) -> str:
        certs = chain or [self.leaf, self.intermediate, self.root]
        x5c = [base64.b64encode(c.public_bytes(Encoding.DER)).decode() for c in certs]
        return jwt.encode(payload, self.leaf_key, algorithm="ES256", headers={"x5c": x5c})


def make_pki(*, leaf_expired: bool = False) -> TestPki:
    root_key = ec.generate_private_key(ec.SECP256R1())
    inter_key = ec.generate_private_key(ec.SECP256R1())
    leaf_key = ec.generate_private_key(ec.SECP256R1())
    root = _cert("Test Root", "Test Root", root_key, root_key, ca=True)
    inter = _cert("Test WWDR", "Test Root", inter_key, root_key, ca=True, marker=INTERMEDIATE_OID)
    leaf = _cert(
        "Test Leaf",
        "Test WWDR",
        leaf_key,
        inter_key,
        ca=False,
        marker=LEAF_OID,
        not_after=datetime.now(UTC) - timedelta(minutes=1) if leaf_expired else None,
    )
    return TestPki(root, inter, leaf, leaf_key)
