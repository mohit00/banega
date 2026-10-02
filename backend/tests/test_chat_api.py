"""Maharaj chat API: sessions, privacy, prototype-text parity, the two-step (cards first, text
later) write, LLM fallbacks, the daily LLM budget, the rate limit and retention.

The Anthropic client is replaced by a fake (no network)."""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import Iterator
from datetime import timedelta
from types import SimpleNamespace
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import delete, func, select

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import ChatMessage, ChatSession, StockItem
from app.services.importer import DEMO_COOK_PHONE, seed_all
from app.services.maharaj.llm import set_llm_client
from app.services.maharaj.parse import LlmParseOut
from app.workers.worker import purge_chat_sessions
from tests.conftest import Headers, Login
from tests.engine_fixtures import seed_recipes
from tests.maharaj_oracle import proto_recipes, reply

DEMO_PHONE = "+919999999999"
QUICK_ASKS = [
    "15 min mein kuch",
    "Kuch halka",
    "Baarish special",
    "Daughter ka tiffin",
    "Mehmaan aa rahe hain",
    "High protein",
]


async def _seed(publish: str = "all") -> None:
    async with get_sessionmaker()() as db:
        await seed_all(db, publish=publish, with_demo_household=True)  # type: ignore[arg-type]
        # The prototype has no pantry: parity is checked with stock unknown (the Phase 6 demo
        # seed marks dahi out, which rightly moves dahi dishes down in the ranking).
        await db.execute(delete(StockItem))
        await db.commit()


async def _session(client: AsyncClient, h: Headers, slot: str | None = "lunch") -> str:
    r = await client.post("/v1/chat/sessions", json={"slot": slot} if slot else None, headers=h)
    assert r.status_code == 200, r.text
    return str(r.json()["session_id"])


async def _ask(client: AsyncClient, h: Headers, sid: str, text: str, **kw: Any) -> Any:
    return await client.post(
        f"/v1/chat/sessions/{sid}/messages", json={"text": text, **kw}, headers=h
    )


class FakeMessages:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.parse_out: LlmParseOut | None = None
        self.parse_exc: BaseException | None = None
        self.write_text = "Kadhi Pakora baarish ke liye ekdum sahi hai."
        self.write_exc: BaseException | None = None

    async def parse(self, **kw: Any) -> Any:
        self.calls.append(("parse", kw))
        if self.parse_exc is not None:
            raise self.parse_exc
        return SimpleNamespace(stop_reason="end_turn", parsed_output=self.parse_out)

    async def create(self, **kw: Any) -> Any:
        self.calls.append(("write", kw))
        if self.write_exc is not None:
            raise self.write_exc
        return SimpleNamespace(
            stop_reason="end_turn", content=[SimpleNamespace(type="text", text=self.write_text)]
        )


class FakeClient:
    def __init__(self) -> None:
        self.messages = FakeMessages()
        self.options: list[dict[str, Any]] = []

    def with_options(self, **kw: Any) -> FakeClient:
        self.options.append(kw)
        return self

    def kinds(self) -> list[str]:
        return [k for k, _ in self.messages.calls]


@pytest.fixture
def fake_llm() -> Iterator[FakeClient]:
    fake = FakeClient()
    set_llm_client(fake)
    yield fake
    set_llm_client(None)


@pytest.fixture
def settings(monkeypatch: pytest.MonkeyPatch) -> Any:
    """Settings object whose attributes the test may change (restored afterwards)."""
    s = get_settings()

    class _S:
        def __setattr__(self, name: str, value: Any) -> None:
            monkeypatch.setattr(s, name, value)

    return _S()


def _parse_out(**kw: Any) -> LlmParseOut:
    base: dict[str, Any] = {
        "slot": None,
        "tags": [],
        "max_mins": None,
        "ingredients_include": [],
        "ingredients_exclude": [],
        "cuisines": [],
        "member_focus": None,
        "guests_adults": None,
        "guests_kids": None,
        "guests_diet": None,
        "diet": None,
        "spice": None,
        "mood": None,
        "language": "hinglish",
        "off_topic": False,
    }
    base.update(kw)
    return LlmParseOut.model_validate(base)


# ---- sessions ---------------------------------------------------------------------------


async def test_session_welcome_and_reuse(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await login(DEMO_PHONE)
    r = (await client.post("/v1/chat/sessions", json={"slot": "lunch"}, headers=h)).json()
    assert r["welcome"]["text"] == (
        "Namaste! Main Maharaj hoon. Ghar ke 5 logon ki pasand mujhe yaad hai.\n"
        "Bas pucho — aaj kya banaun?"
    )
    assert r["welcome"]["chips"] == [
        "Aaj lunch mein kya?",
        "Kuch halka dinner",
        "15 min mein nashta",
        "Mehmaan aa rahe hain",
    ]
    assert r["reused"] is False and r["slot"] == "lunch"
    again = (await client.post("/v1/chat/sessions", headers=h)).json()
    assert again["reused"] is True and again["session_id"] == r["session_id"]
    # A slot change starts a new session (F-5.4-03).
    other = (await client.post("/v1/chat/sessions", json={"slot": "dinner"}, headers=h)).json()
    assert other["session_id"] != r["session_id"] and other["slot"] == "dinner"


async def test_quick_asks_match_prototype_texts(
    client: AsyncClient, login: Login, settings: Any
) -> None:
    """The template writer reproduces the prototype's reply() text, cards and chips for the
    six quick asks with the demo household (prototype relaxation: only when nothing
    matches)."""
    settings.MAHARAJ_MIN_RESULTS = 1
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    proto = proto_recipes({s.view.id: s.view.jain_safe for s in seed_recipes()})
    for ask in QUICK_ASKS:
        r = await _ask(client, h, sid, ask, slot="lunch")
        assert r.status_code == 200, r.text
        body = r.json()
        oracle = reply(ask, "lunch", proto)
        assert body["text"] == oracle["text"], ask
        assert [c["slug"] for c in body["cards"]] == oracle["recipes"], ask
        assert body["chips"] == oracle["chips"]
        assert body["status"] == "complete" and body["slot"] == "lunch"


async def test_cards_have_the_recommendations_shape(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    cards = (await _ask(client, h, sid, "Aaj lunch mein kya?")).json()["cards"]
    reco = (await client.get("/v1/recommendations?slot=lunch", headers=h)).json()
    tiles = {t["recipe"]["slug"]: t["recipe"] for t in [reco["pick"], *reco["tiles"]]}
    assert cards
    common = [c for c in cards if c["slug"] in tiles]
    assert common
    for card in common:
        assert card == tiles[card["slug"]]


async def test_history_is_paginated_oldest_first(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    await _ask(client, h, sid, "Kuch halka")
    await _ask(client, h, sid, "Paneer wala kuch")
    page = (await client.get(f"/v1/chat/sessions/{sid}/messages?limit=3", headers=h)).json()
    assert [m["author"] for m in page["items"]] == ["user", "bot", "user"]
    assert page["items"][0]["text"] == "Kuch halka"
    assert page["items"][1]["cards"] and page["items"][1]["chips"]
    assert page["next_cursor"]
    rest = (
        await client.get(
            f"/v1/chat/sessions/{sid}/messages?cursor={page['next_cursor']}", headers=h
        )
    ).json()
    assert [m["author"] for m in rest["items"]] == ["bot"] and rest["next_cursor"] is None
    assert rest["items"][0]["cards"][0]["slug"] in {"pbm", "palak"}


# ---- privacy (F-5.4-01) -----------------------------------------------------------------


async def _join(
    client: AsyncClient, admin: Headers, login: Login, phone: str, role: str
) -> Headers:
    token = (
        await client.post("/v1/invites", json={"phone": phone, "role": role}, headers=admin)
    ).json()["token"]
    h = await login(phone)
    assert (await client.post(f"/v1/invites/{token}/accept", headers=h)).status_code == 200
    return h


async def test_sessions_are_private(client: AsyncClient, login: Login, make_household: Any) -> None:
    await _seed()
    admin = await login(DEMO_PHONE)
    sid = await _session(client, admin)
    msg = (await _ask(client, admin, sid, "Kuch halka")).json()["message_id"]

    member = await _join(client, admin, login, "+919800000011", "member")
    stranger = await make_household("+919800000012", "Doosra ghar")
    for h in (member, stranger):
        assert (await client.get(f"/v1/chat/sessions/{sid}/messages", headers=h)).status_code == 404
        assert (await _ask(client, h, sid, "Kuch halka")).status_code == 404
        assert (await client.get(f"/v1/chat/messages/{msg}", headers=h)).status_code == 404
    # The member's own session is theirs alone; the admin cannot read it either.
    mine = await _session(client, member)
    assert mine != sid
    assert (
        await client.get(f"/v1/chat/sessions/{mine}/messages", headers=admin)
    ).status_code == 404


async def test_hired_cook_has_no_chat(client: AsyncClient, login: Login) -> None:
    await _seed()
    admin = await login(DEMO_PHONE)
    sid = await _session(client, admin)
    cook = await login(DEMO_COOK_PHONE)  # the seeded hired cook: cook mode only
    r = await client.post("/v1/chat/sessions", headers=cook)
    assert r.status_code == 403 and r.json()["code"] == "forbidden"
    assert (await _ask(client, cook, sid, "Kuch halka")).status_code == 403
    assert (await client.get(f"/v1/chat/sessions/{sid}/messages", headers=cook)).status_code == 403


async def test_expired_session_is_gone(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    async with get_sessionmaker()() as db:
        s = await db.get(ChatSession, uuid.UUID(sid))
        assert s is not None
        s.expires_at = utcnow() - timedelta(minutes=1)
        await db.commit()
    r = await _ask(client, h, sid, "Kuch halka")
    assert r.status_code == 410 and r.json()["code"] == "chat_session_expired"
    fresh = (await client.post("/v1/chat/sessions", headers=h)).json()
    assert fresh["session_id"] != sid and fresh["reused"] is False


# ---- LLM path ---------------------------------------------------------------------------


async def test_two_step_text_fill(client: AsyncClient, login: Login, fake_llm: FakeClient) -> None:
    await _seed()
    fake_llm.messages.parse_out = _parse_out(tags=["rainy"])
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    r = await _ask(client, h, sid, "baarish mein kya banau")
    assert r.status_code == 200, r.text
    body = r.json()
    # Cards and chips come back at once; the text is filled by the write job.
    assert body["text"] is None and body["status"] == "pending"
    assert "kadhi" in [c["slug"] for c in body["cards"]]
    assert body["chips"]
    status = (await client.get(f"/v1/chat/messages/{body['message_id']}", headers=h)).json()
    assert status == {
        "message_id": body["message_id"],
        "text": "Kadhi Pakora baarish ke liye ekdum sahi hai.",
        "status": "complete",
    }
    assert fake_llm.kinds() == ["parse", "write"]
    parse_kw = fake_llm.messages.calls[0][1]
    assert parse_kw["model"] == get_settings().MAHARAJ_PARSE_MODEL
    assert parse_kw["output_format"] is LlmParseOut and parse_kw["max_tokens"] == 300
    assert "<query>baarish mein kya banau</query>" in parse_kw["messages"][0]["content"]
    # Sonnet 5: no sampling params (rejected), thinking off, low effort.
    assert parse_kw["thinking"] == {"type": "disabled"}
    assert parse_kw["output_config"] == {"effort": "low"}
    write_kw = fake_llm.messages.calls[1][1]
    assert "temperature" not in write_kw and "extra_body" not in write_kw
    assert write_kw["max_tokens"] == 200 and write_kw["model"] == get_settings().MAHARAJ_WRITE_MODEL
    assert {"timeout": 2.5, "max_retries": 0} in fake_llm.options
    assert {"timeout": 3.0, "max_retries": 0} in fake_llm.options
    # The same text again: parse comes from the 24 h cache.
    await _ask(client, h, sid, "Baarish mein kya banau?")
    assert fake_llm.kinds() == ["parse", "write", "write"]
    async with get_sessionmaker()() as db:
        bot = (
            (
                await db.execute(
                    select(ChatMessage)
                    .where(ChatMessage.author == "bot")
                    .order_by(ChatMessage.created_at)
                )
            )
            .scalars()
            .first()
        )
        assert bot is not None and bot.latency_ms is not None
        assert set(bot.latency_ms) == {"parse", "retrieve", "rank", "write"}
        assert bot.parsed_filters is not None
        assert bot.parsed_filters["query"]["source"] == "llm"
        assert bot.parsed_filters["write_source"] == "llm"


async def test_llm_failures_fall_back(
    client: AsyncClient, login: Login, fake_llm: FakeClient
) -> None:
    await _seed()
    fake_llm.messages.parse_exc = TimeoutError()
    fake_llm.messages.write_exc = TimeoutError()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    body = (await _ask(client, h, sid, "Kuch halka", slot="lunch")).json()
    status = (await client.get(f"/v1/chat/messages/{body['message_id']}", headers=h)).json()
    assert status["status"] == "complete"
    assert status["text"].startswith("Lunch ke liye 4 options — halka.\n")

    # A reply naming a dish that is not on the cards fails validation: template instead.
    fake_llm.messages.parse_exc = None
    fake_llm.messages.write_exc = None
    fake_llm.messages.parse_out = _parse_out(tags=["light"])
    fake_llm.messages.write_text = "Chicken Curry banao, sabko pasand aayega."
    body = (await _ask(client, h, sid, "halka khana", slot="lunch")).json()
    status = (await client.get(f"/v1/chat/messages/{body['message_id']}", headers=h)).json()
    assert status["text"].startswith("Lunch ke liye 4 options — halka.")


async def test_off_topic_gets_the_fixed_reply(
    client: AsyncClient, login: Login, fake_llm: FakeClient
) -> None:
    await _seed()
    fake_llm.messages.parse_out = _parse_out(off_topic=True)
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    body = (await _ask(client, h, sid, "cricket score kya hai?")).json()
    assert body["cards"] == [] and body["status"] == "complete"
    assert body["text"] == "Main sirf khaane mein madad karta hoon."
    assert fake_llm.kinds() == ["parse"]


async def test_daily_budget_falls_back_to_rules_and_templates(
    client: AsyncClient, login: Login, fake_llm: FakeClient, settings: Any
) -> None:
    await _seed()
    fake_llm.messages.parse_out = _parse_out(tags=["light"])
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)

    settings.MAHARAJ_DAILY_BUDGET = 1
    # The one allowed call goes to parse; the writer has no budget left: inline template.
    body = (await _ask(client, h, sid, "kuch halka sa", slot="lunch")).json()
    assert fake_llm.kinds() == ["parse"]
    assert body["status"] == "complete" and body["text"].startswith("Lunch ke liye")
    # Budget spent: rule parser + template, no LLM call at all.
    body = (await _ask(client, h, sid, "Mehmaan aa rahe hain", slot="lunch")).json()
    assert fake_llm.kinds() == ["parse"]
    assert body["text"].startswith("Lunch ke liye 4 options — mehmaan-worthy.")

    settings.MAHARAJ_DAILY_BUDGET = 0
    body = (await _ask(client, h, sid, "High protein", slot="lunch")).json()
    assert fake_llm.kinds() == ["parse"] and body["text"]


async def test_no_key_means_rules_and_templates(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    body = (await _ask(client, h, sid, "Kuch halka dinner")).json()
    assert body["status"] == "complete" and body["slot"] == "dinner"
    assert body["text"].startswith("Dinner ke liye 4 options — halka.")


# ---- rate limit and retention -----------------------------------------------------------


async def test_rate_limit(client: AsyncClient, login: Login, settings: Any) -> None:
    settings.MAHARAJ_RATE_LIMIT = 3
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    for _ in range(3):
        assert (await _ask(client, h, sid, "Kuch halka")).status_code == 200
    r = await _ask(client, h, sid, "Kuch halka")
    assert r.status_code == 429 and r.json()["code"] == "chat_rate_limited"


async def test_retention_job_deletes_idle_sessions(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await login(DEMO_PHONE)
    old = await _session(client, h, "lunch")
    await _ask(client, h, old, "Kuch halka")
    recent = await _session(client, h, "dinner")
    async with get_sessionmaker()() as db:
        s = await db.get(ChatSession, uuid.UUID(old))
        assert s is not None
        s.last_active_at = utcnow() - timedelta(days=31)
        await db.commit()
    assert await purge_chat_sessions({}) == {"sessions": 1}
    async with get_sessionmaker()() as db:
        assert await db.get(ChatSession, uuid.UUID(old)) is None
        assert await db.get(ChatSession, uuid.UUID(recent)) is not None
        left = (
            await db.execute(
                select(func.count())
                .select_from(ChatMessage)
                .where(ChatMessage.session_id == uuid.UUID(old))
            )
        ).scalar_one()
        assert left == 0


async def test_parse_timeout_is_bounded(
    client: AsyncClient, login: Login, fake_llm: FakeClient, settings: Any
) -> None:
    """A parse call that hangs is cut at the timeout and the rule parser answers."""
    settings.MAHARAJ_PARSE_TIMEOUT = 0.05
    settings.MAHARAJ_LLM_WRITE = False
    await _seed()

    async def slow(**kw: Any) -> Any:
        await asyncio.sleep(5)

    fake_llm.messages.parse = slow  # type: ignore[method-assign]
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    body = (await _ask(client, h, sid, "Kuch halka", slot="lunch")).json()
    assert body["status"] == "complete"
    assert body["text"].startswith("Lunch ke liye 4 options — halka.")


async def test_llm_never_sees_untyped_names_allergens_or_health(
    client: AsyncClient, login: Login, fake_llm: FakeClient
) -> None:
    """F-7-02 / review B1: the write prompt carries anonymised constraints only."""
    await _seed()
    async with get_sessionmaker()() as db:
        from app.models import Member

        members = {m.name: m for m in (await db.execute(select(Member))).scalars()}
        members["Mummy"].allergens = ["peanut"]
        members["Wife"].allergens = ["sesame", "peanut"]
        await db.commit()
    fake_llm.messages.parse_out = _parse_out(tags=["rainy"])
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    r = await _ask(client, h, sid, "Dadi ke liye baarish mein kya banau")
    assert r.status_code == 200, r.text
    await client.get(f"/v1/chat/messages/{r.json()['message_id']}", headers=h)

    prompts = [
        kw["system"] + "".join(m["content"] for m in kw["messages"])
        for kind, kw in fake_llm.messages.calls
    ]
    write_prompt = next(
        kw["messages"][0]["content"] for kind, kw in fake_llm.messages.calls if kind == "write"
    )
    for text in prompts:
        for untyped in ("Papa", "Mummy", "Daughter", "Wife"):
            assert untyped not in text, (untyped, text)
    # The generic system prompts mention tags; the family's facts never carry health needs.
    for health in ("low sugar", "Low sugar", "low oil", "Low oil", "protein"):
        assert health not in write_prompt
    # Allergies go as anonymous counts, never next to a name; the typed member is named.
    assert "two peanut allergy" in write_prompt and "one sesame allergy" in write_prompt
    assert "Dadi: Jain" in write_prompt
    assert "one mild spice eater" in write_prompt
    assert "Mummy (peanut" not in write_prompt


async def test_chips_follow_the_request_language(client: AsyncClient, login: Login) -> None:
    """Welcome text and chips come back in the app's language (Accept-Language); Hinglish is
    the fallback, and the user's saved locale is used when the header says nothing."""
    await _seed()
    h = await login(DEMO_PHONE)
    en = {**h, "Accept-Language": "en-IN"}
    r = (await client.post("/v1/chat/sessions", json={"slot": "lunch"}, headers=en)).json()
    assert r["welcome"]["text"].startswith("Namaste! I'm Maharaj.")
    assert r["welcome"]["chips"][0] == "What's for lunch today?"
    reply_en = (await _ask(client, en, r["session_id"], "Kuch halka", slot="lunch")).json()
    assert reply_en["chips"] == [
        "Something light",
        "Rainy-day special",
        "Something with paneer",
        "What for Dadi?",
    ]

    hi = {**h, "Accept-Language": "hi"}
    r = (await client.post("/v1/chat/sessions", json={"slot": "nashta"}, headers=hi)).json()
    assert r["welcome"]["chips"][0] == "आज लंच में क्या?"
    reply_hi = (await _ask(client, hi, r["session_id"], "Kuch halka", slot="nashta")).json()
    assert reply_hi["chips"][0] == "प्रोटीन वाला नाश्ता"

    hinglish = {**h, "Accept-Language": "hi-Latn"}
    r = (await client.post("/v1/chat/sessions", json={"slot": "dinner"}, headers=hinglish)).json()
    assert r["welcome"]["chips"][0] == "Aaj lunch mein kya?"
    reply_hl = (await _ask(client, hinglish, r["session_id"], "Kuch halka", slot="dinner")).json()
    assert reply_hl["chips"][0] == "Kuch halka"


async def test_translated_chips_ask_the_same_thing(client: AsyncClient, login: Login) -> None:
    """Tapping an English or Hindi chip finds the same dishes as its Hinglish original."""
    await _seed()
    h = await login(DEMO_PHONE)
    sid = await _session(client, h)
    from app.services.maharaj.pipeline import DEFAULT_CONFIG

    for lang in ("en", "hi"):
        pairs = zip(
            DEFAULT_CONFIG["follow_ups"]["lunch"],
            DEFAULT_CONFIG[f"follow_ups_{lang}"]["lunch"],
            strict=True,
        )
        for base, translated in pairs:
            a = (await _ask(client, h, sid, base, slot="lunch")).json()
            b = (await _ask(client, h, sid, translated, slot="lunch")).json()
            assert [c["slug"] for c in a["cards"]] == [c["slug"] for c in b["cards"]], translated
