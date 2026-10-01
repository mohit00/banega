"""Hinglish display labels shared by share texts and notifications."""

from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

SLOT_LABEL: dict[str, str] = {
    "nashta": "Nashta",
    "lunch": "Lunch",
    "dinner": "Dinner",
    "tiffin": "Tiffin",
    "shaam": "Shaam ka nashta",
}

WEEKDAY_HI: tuple[str, ...] = (
    "Somvar",
    "Mangalvar",
    "Budhvar",
    "Guruvar",
    "Shukravar",
    "Shanivar",
    "Ravivar",
)

MONTH_SHORT: tuple[str, ...] = (
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
)


def slot_label(slot: str) -> str:
    return SLOT_LABEL.get(slot, slot.title())


def day_label(d: date) -> str:
    """Weekday and date, e.g. Shanivar, 26 Sep."""
    return f"{WEEKDAY_HI[d.weekday()]}, {d.day} {MONTH_SHORT[d.month - 1]}"


def time_label(dt: datetime, tz: str) -> str:
    """Household-local 12 h clock: "1:30 PM"."""
    local = dt.astimezone(ZoneInfo(tz or "Asia/Kolkata"))
    hour = local.hour % 12 or 12
    return f"{hour}:{local.minute:02d} {'AM' if local.hour < 12 else 'PM'}"


def mask_phone(phone: str | None) -> str | None:
    """Keep the country code and the last 4 digits: +91******9990."""
    if not phone:
        return None
    if len(phone) <= 7:
        return "*" * len(phone)
    head = phone[:3] if phone.startswith("+") else ""
    tail = phone[-4:]
    return head + "*" * (len(phone) - len(head) - 4) + tail
