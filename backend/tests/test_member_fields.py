"""Member.vrat_days and Member.show_on_home (client fields; F-5.3-05)."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

from httpx import AsyncClient

from app.engine import EaterView, Need, constraint_line
from app.services.maharaj.write import constraint_line as chat_line
from app.services.maharaj.write import llm_constraints
from tests.kitchen_fixtures import seed_catalogue


async def test_member_fields_round_trip(client: AsyncClient, make_household: Any) -> None:
    h = await make_household()
    r = await client.post(
        "/v1/members",
        json={"name": "Dadi", "vrat_days": [3, 0, 3], "show_on_home": True},
        headers=h,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["vrat_days"] == [0, 3] and body["show_on_home"] is True
    r = await client.patch(
        f"/v1/members/{body['id']}", json={"vrat_days": [], "show_on_home": False}, headers=h
    )
    assert r.json()["vrat_days"] == [] and r.json()["show_on_home"] is False
    bad = await client.post("/v1/members", json={"name": "X", "vrat_days": [7]}, headers=h)
    assert bad.status_code == 422
    plain = await client.post("/v1/members", json={"name": "Y"}, headers=h)
    assert plain.json()["vrat_days"] == [] and plain.json()["show_on_home"] is False


def _next(weekday: int) -> date:
    d = date.today() + timedelta(days=1)
    while d.weekday() != weekday:
        d += timedelta(days=1)
    return d


async def test_vrat_day_turns_on_the_vrat_rule(client: AsyncClient, make_household: Any) -> None:
    await seed_catalogue()
    h = await make_household()
    thursday = _next(3)
    await client.post("/v1/members", json={"name": "Dadi", "vrat_days": [3]}, headers=h)

    async def keys(day: date) -> list[str]:
        r = await client.get(f"/v1/recommendations?slot=lunch&date={day.isoformat()}", headers=h)
        assert r.status_code == 200, r.text
        return [i["key"] for i in r.json()["constraint_line"]["items"]]

    assert "vrat" in await keys(thursday)
    assert "vrat" not in await keys(thursday + timedelta(days=1))


def test_health_needs_only_for_show_on_home() -> None:
    papa = EaterView(id="p", name="Papa", needs=frozenset({Need.low_sugar}))
    shown = EaterView(id="m", name="Mummy", needs=frozenset({Need.low_sugar}), show_on_home=True)
    items, _ = constraint_line([papa, shown])
    assert [(i.key, i.params["name"]) for i in items] == [("low_sugar", "Mummy")]
    assert "Mummy (low sugar)" in chat_line([papa, shown])
    assert "Papa" not in chat_line([papa, shown])
    # Never to the LLM, whatever the member chose.
    assert not any("sugar" in c for c in llm_constraints([papa, shown], ["Mummy", "Papa"]))
