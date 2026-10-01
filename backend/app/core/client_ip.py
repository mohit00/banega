"""The caller's IP address behind trusted proxies (nginx, a load balancer).

``X-Forwarded-For`` is honoured only when the direct peer is a trusted proxy; the client is
then the right-most address that is not itself a trusted proxy (every proxy appends the
address it saw, so everything left of that is client-controlled and ignored).
"""

from __future__ import annotations

import ipaddress
from functools import lru_cache

from starlette.requests import Request

from app.core.config import get_settings

Network = ipaddress.IPv4Network | ipaddress.IPv6Network


@lru_cache(maxsize=8)
def _networks(spec: str) -> tuple[Network, ...]:
    out: list[Network] = []
    for part in spec.split(","):
        part = part.strip()
        if part:
            out.append(ipaddress.ip_network(part, strict=False))
    return tuple(out)


def is_trusted(addr: str | None) -> bool:
    if not addr:
        return False
    try:
        ip = ipaddress.ip_address(addr.strip())
    except ValueError:
        return False
    return any(ip in net for net in _networks(get_settings().TRUSTED_PROXIES))


def client_ip(request: Request) -> str:
    peer = request.client.host if request.client else ""
    forwarded = request.headers.get("x-forwarded-for")
    if not forwarded or not is_trusted(peer):
        return peer or "unknown"
    hops = [h.strip() for h in forwarded.split(",") if h.strip()]
    for hop in reversed(hops):
        if not is_trusted(hop):
            return hop
    return hops[0] if hops else peer or "unknown"
