"""Phase 7: ratings (upsert, proxy, masking, disabled), rate prompts, served history, the
learning / repetition / stock terms in the engine score, and the weekly insights."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.engine import rank
from app.models import Household, Member, Recipe, RecipeStatus, ServedHistory
from app.services import learning
from app.services import menus as menu_svc
from app.services.catalogue import eater_view, recipe_view
from app.services.learning import to_five
from tests.conftest import Login
from tests.kitchen_fixtures import Kitchen, make_kitchen
from tests.pantry_fixtures import complete, hired_ticket, household_id, inbox_events, ing


def _rid(t: dict[str, Any], prefix: str) -> str:
    return str(next(d["recipe_id"] for d in t["dishes"] if d["name"].lower().startswith(prefix)))


async def _rate(k: Kitchen, t: dict[str, Any], headers: dict[str, str], *items: Any) -> Any:
    body = {"ratings": [{"recipe_id": r, "member_id": m, "score": s} for r, m, s in items]}
    return await k.client.post(f"/v1/tickets/{t['id']}/ratings", json=body, headers=headers)


async def test_ratings_upsert_proxy_and_prompt(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    mummy_h = await k.invite_member(member="Mummy")
    t, cook_h = await hired_ticket(k)
    gatte = _rid(t, "gatte")
    papa, mummy, beta = k.members["Papa"], k.members["Mummy"], k.members["Beta"]

    r = await _rate(k, t, k.admin, (gatte, papa, 3))
    assert r.status_code == 409 and r.json()["code"] == "not_completed"

    done = await complete(k, t, cook_h)
    assert done["rated_at"] is None
    assert "rate_prompt" in await inbox_events(k, k.admin)  # confirmer + admin

    # Own rating + proxy for a profile-only kid; not for a member who has her own login.
    r = await _rate(k, t, k.admin, (gatte, papa, 3), (gatte, beta, 2))
    assert r.status_code == 200, r.text
    first_rated = r.json()["rated_at"]
    assert first_rated is not None and r.json()["status"] == "completed"
    r = await _rate(k, t, k.admin, (gatte, mummy, 1))
    assert r.status_code == 403 and r.json()["code"] == "not_your_rating"
    r = await _rate(k, t, mummy_h, (gatte, mummy, 1))
    assert r.status_code == 200
    # A hired cook never rates.
    r = await _rate(k, t, cook_h, (gatte, papa, 3))
    assert r.status_code == 403

    # Upsert: same (ticket, recipe, member) changes the score, not the count.
    r = await _rate(k, t, k.admin, (gatte, papa, 1))
    assert r.json()["rated_at"] == first_rated
    rows = (await client.get(f"/v1/tickets/{t['id']}/ratings", headers=k.admin)).json()
    assert len(rows["ratings"]) == 3
    assert {x["score"] for x in rows["ratings"] if x["member_id"] == papa} == {1}

    # Validation: a dish or eater that is not on the meal; scores are 1..3.
    r = await _rate(k, t, k.admin, (str(uuid.uuid4()), papa, 2))
    assert r.status_code == 422 and r.json()["code"] == "not_on_ticket"
    r = await _rate(k, t, k.admin, (gatte, papa, 4))
    assert r.status_code == 422


async def test_summary_masks_names_for_hired_cook(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    mummy_h = await k.invite_member(member="Mummy")
    t, cook_h = await hired_ticket(k)
    await complete(k, t, cook_h)
    gatte = _rid(t, "gatte")
    await _rate(k, t, k.admin, (gatte, k.members["Papa"], 3), (gatte, k.members["Beta"], 2))
    await _rate(k, t, mummy_h, (gatte, k.members["Mummy"], 1))

    admin_view = (
        await client.get(f"/v1/ratings/summary?recipe_id={gatte}", headers=k.admin)
    ).json()
    assert admin_view[0]["count"] == 3 and admin_view[0]["average"] == 2.0
    assert {m["name"] for m in admin_view[0]["members"]} == {"Papa", "Mummy", "Beta"}

    cook_view = (await client.get("/v1/ratings/summary", headers=cook_h)).json()
    assert cook_view[0]["average"] == 2.0 and cook_view[0]["members"] == []
    body = str(cook_view)
    assert "Papa" not in body and "Mummy" not in body and "Beta" not in body
    # The ticket ratings list masks names for anybody who may not see them.
    mummy_rows = (await client.get(f"/v1/tickets/{t['id']}/ratings", headers=mummy_h)).json()
    names = {x["member_name"] for x in mummy_rows["ratings"]}
    assert "Mummy" in names and "Papa" not in names

    # An adult member sees her own ratings by name only.
    mummy_view = (await client.get("/v1/ratings/summary", headers=mummy_h)).json()
    assert [m["name"] for m in mummy_view[0]["members"]] == ["Mummy"]

    await client.patch("/v1/households/me", json={"show_names_to_cook": True}, headers=k.admin)
    cook_view = (await client.get("/v1/ratings/summary", headers=cook_h)).json()
    assert {m["name"] for m in cook_view[0]["members"]} == {"Papa", "Mummy", "Beta"}


async def test_ratings_disabled(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)  # the hired cook is the primary
    mummy_h = await k.invite_member(member="Mummy")
    await k.add_family("Mummy")
    # A family cook may switch ratings off herself (F-5.10-04); other settings stay admin-only.
    r = await client.patch("/v1/households/me", json={"ratings_enabled": False}, headers=mummy_h)
    assert r.status_code == 200 and r.json()["household"]["ratings_enabled"] is False
    r = await client.patch("/v1/households/me", json={"auto_decrement": True}, headers=mummy_h)
    assert r.status_code == 403
    await complete(k, t, cook_h)
    assert "rate_prompt" not in await inbox_events(k, k.admin)
    r = await _rate(k, t, k.admin, (_rid(t, "gatte"), k.members["Papa"], 3))
    assert r.status_code == 409 and r.json()["code"] == "ratings_disabled"


# ---- learning ------------------------------------------------------------------------------


async def _positions(hid: uuid.UUID, slot: str = "lunch") -> dict[str, float]:
    """Engine scores for every published recipe in ``slot`` with the learning context."""
    async with get_sessionmaker()() as db:
        household = await db.get(Household, hid)
        assert household is not None
        members = list(
            (await db.execute(select(Member).where(Member.household_id == hid))).scalars()
        )
        recipes = list(
            (
                await db.execute(select(Recipe).where(Recipe.status == RecipeStatus.published))
            ).scalars()
        )
        ctx = await learning.score_context(db, household, menu_svc.local_today(household, utcnow()))
        ranking = rank(
            [recipe_view(r) for r in recipes],
            [eater_view(m) for m in members],
            ctx,
            slot,
            grid_size=50,
            max_per_category=50,
        )
        items = [ranking.pick, *ranking.tiles] if ranking.pick else []
        return {x.recipe.id: x.score for x in items if x is not None}


def test_score_scale() -> None:
    assert (to_five(1), to_five(2), to_five(3)) == (1.0, 3.0, 5.0)


async def test_learning_repetition_and_stock_change_scores(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    hid = await household_id(k)
    base = await _positions(hid)
    t, cook_h = await hired_ticket(k, ["gatte", "bhindi"])
    gatte, bhindi = _rid(t, "gatte"), _rid(t, "bhindi")

    # Cancelled tickets never count: no served history.
    other = await k.menu(["palak"], slot="dinner")
    t_cancel = (await k.confirm(other)).json()["ticket"]
    assert (await k.move(t_cancel, "cancelled")).status_code == 200

    await complete(k, t, cook_h)
    async with get_sessionmaker()() as db:
        served = {
            str(r)
            for r in (
                await db.execute(
                    select(ServedHistory.recipe_id).where(ServedHistory.ticket_id.is_not(None))
                )
            ).scalars()
        }
    assert served == {gatte, bhindi}

    # Repetition: both served dishes lose 25 (served today, within 3 days).
    after_served = await _positions(hid)
    assert after_served[gatte] == base[gatte] - 25
    assert after_served[bhindi] == base[bhindi] - 25

    # Learning: Papa and Beta love bhindi (3 -> 5 on the engine scale: +4 each) and dislike
    # gatte (1 -> 1: -8 each).
    ratings = [(bhindi, m, 3) for m in (k.members["Papa"], k.members["Beta"])]
    ratings += [(gatte, m, 1) for m in (k.members["Papa"], k.members["Beta"])]
    r = await _rate(k, t, k.admin, *ratings)
    assert r.status_code == 200, r.text
    learned = await _positions(hid)
    assert learned[bhindi] - after_served[bhindi] == 8  # 2 eaters x +4
    assert learned[gatte] - after_served[gatte] == -16

    # Stock: once levels exist, all-in recipes gain +3 and each Out tracked item costs 5.
    await client.get("/v1/stock", headers=k.admin)  # materialise: all in
    in_stock = await _positions(hid)
    assert in_stock[gatte] == learned[gatte] + 3
    await client.put(f"/v1/stock/{await ing('curd')}", json={"level": "out"}, headers=k.admin)
    out = await _positions(hid)
    assert out[gatte] == learned[gatte] - 5
    assert out[bhindi] == in_stock[bhindi]  # bhindi has no curd

    # The rank order moves: the liked dish climbs, the disliked / served / out-of-stock one
    # drops.
    def order(scores: dict[str, float]) -> list[str]:
        return sorted(scores, key=lambda rid: (-scores[rid], rid))

    assert base[gatte] > base[bhindi] and out[bhindi] > out[gatte]  # the pair flipped
    assert order(out).index(bhindi) < order(out).index(gatte)
    assert order(base).index(bhindi) > order(base).index(gatte)
    assert order(out).index(gatte) > order(base).index(gatte)

    # /v1/recommendations uses the same context (cache key includes the signals).
    reco = (await client.get("/v1/recommendations?slot=lunch", headers=k.admin)).json()
    tiles = {x["recipe"]["id"]: x["score"] for x in [reco["pick"], *reco["tiles"]] if x}
    if gatte in tiles:
        assert tiles[gatte] == out[gatte]


async def test_weekly_insights(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)
    await complete(k, t, cook_h)
    gatte = _rid(t, "gatte")
    await _rate(k, t, k.admin, (gatte, k.members["Papa"], 3))
    r = await client.get(f"/v1/insights/weekly?end={t['date']}", headers=k.admin)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["meals_cooked"] == 1 and body["completed"] == 1
    assert body["on_time_pct"] == 100.0  # completed well before due_at + 15 min
    assert body["coverage"]["meals"] == 1 and 0 <= body["coverage_pct"] <= 100
    top = body["top_dishes"]
    assert top[0]["recipe_id"] == gatte and top[0]["count"] == 1 and top[0]["avg"] == 3.0
    # An empty week reads 0, not null.
    empty = (await client.get("/v1/insights/weekly?end=2020-01-07", headers=k.admin)).json()
    assert empty["meals_cooked"] == 0 and empty["on_time_pct"] == 0.0
