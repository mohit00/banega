"""Glue for the chat API and the worker: config, rate limit, LLM budget, parse cache,
parse -> retrieve -> rank synchronously, and the (possibly asynchronous) write.

Latency budget per stage (F-5.4-02, p90): parse 1.2 s (timeout 2.5 s), retrieve + rank
300 ms, write 3 s timeout. Every reply logs ``maharaj_reply`` with the per-stage ms; the
write stage logs ``maharaj_write``.
"""

from __future__ import annotations

import hashlib
import time
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import structlog
from sqlalchemy import Select, delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.errors import TooManyRequests
from app.core.kv import get_kv
from app.core.security import utcnow
from app.engine import Ranked
from app.models import (
    AppConfig,
    ChatAuthor,
    ChatMessage,
    ChatMessageStatus,
    ChatSession,
    Household,
    Member,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
    User,
)
from app.services import catalogue_cache
from app.services.catalogue import eater_view
from app.services.maharaj import llm
from app.services.maharaj.parse import LlmParser, RuleParser, cache_text
from app.services.maharaj.retrieve import Retrieval, retrieve
from app.services.maharaj.types import Lang, ParsedQuery, Slot
from app.services.maharaj.write import LlmWriter, ReplyFacts, TemplateWriter, build_facts

log = structlog.get_logger(__name__)

# The prototype's texts; AppConfig rows (seeded from content/app-config.seed.json) win.
DEFAULT_CONFIG: dict[str, Any] = {
    "welcome": "Namaste! Main Maharaj hoon. Ghar ke {n} logon ki pasand mujhe yaad hai.\n"
    "Bas pucho — aaj kya banaun?",
    "welcome_chips": [
        "Aaj lunch mein kya?",
        "Kuch halka dinner",
        "15 min mein nashta",
        "Mehmaan aa rahe hain",
    ],
    "follow_ups": {
        "nashta": ["Protein wala nashta", "Daughter ka tiffin", "Kuch South Indian"],
        "lunch": ["Kuch halka", "Baarish special", "Paneer wala kuch", "Dadi ke liye kya?"],
        "dinner": ["Kuch halka", "Baarish special", "Paneer wala kuch", "Dadi ke liye kya?"],
    },
    "slots": [
        {"key": "nashta", "label": "Nashta"},
        {"key": "lunch", "label": "Lunch"},
        {"key": "dinner", "label": "Dinner"},
    ],
}
CHAT_SLOTS: tuple[Slot, ...] = ("nashta", "lunch", "dinner")


async def load_config(db: AsyncSession) -> dict[str, Any]:
    keys = list(DEFAULT_CONFIG)
    rows = (await db.execute(select(AppConfig).where(AppConfig.key.in_(keys)))).scalars()
    cfg = dict(DEFAULT_CONFIG)
    cfg.update({r.key: r.value for r in rows})
    return cfg


def follow_ups(cfg: dict[str, Any], slot: str) -> list[str]:
    fu = cfg.get("follow_ups") or {}
    chips = fu.get(slot) or DEFAULT_CONFIG["follow_ups"].get(slot) or []
    return [str(c) for c in chips]


def slot_label_from(cfg: dict[str, Any], slot: str) -> str:
    for s in cfg.get("slots") or []:
        if isinstance(s, dict) and s.get("key") == slot and s.get("label"):
            return str(s["label"])
    return slot.title()


def chat_slot(slot: str | None) -> Slot:
    return slot if slot in CHAT_SLOTS else "lunch"


def local_day(household: Household) -> date:
    return datetime.now(ZoneInfo(household.timezone or "Asia/Kolkata")).date()


# ---- rate limit and budget -----------------------------------------------------------------


async def check_rate_limit(user_id: uuid.UUID) -> None:
    s = get_settings()
    window = s.MAHARAJ_RATE_WINDOW_SECONDS
    bucket = int(time.time() // window)
    count = await get_kv().incr(f"maharaj:rl:{user_id}:{bucket}", window)
    if count > s.MAHARAJ_RATE_LIMIT:
        raise TooManyRequests(
            "chat_rate_limited",
            "Too many messages. Please wait a few minutes.",
            "Bahut saare sawaal ho gaye. Thodi der baad poochhiye.",
            details={"limit": s.MAHARAJ_RATE_LIMIT, "window_seconds": window},
        )


def _budget_key(household_id: uuid.UUID, day: date) -> str:
    return f"maharaj:budget:{household_id}:{day.isoformat()}"


async def budget_left(household_id: uuid.UUID, day: date) -> int:
    used = int(await get_kv().get(_budget_key(household_id, day)) or 0)
    return max(0, get_settings().MAHARAJ_DAILY_BUDGET - used)


async def take_budget(household_id: uuid.UUID, day: date) -> bool:
    """Reserve one LLM call; False once the household's daily budget is spent."""
    budget = get_settings().MAHARAJ_DAILY_BUDGET
    if budget <= 0:
        return False
    used = await get_kv().incr(_budget_key(household_id, day), 2 * 24 * 3600)
    return used <= budget


# ---- parse ---------------------------------------------------------------------------------


def _parse_cache_key(household_id: uuid.UUID, text: str, members: list[str]) -> str:
    src = "|".join(
        [cache_text(text), ",".join(sorted(members)), get_settings().MAHARAJ_PARSE_MODEL]
    )
    return f"maharaj:parse:{household_id}:{hashlib.sha256(src.encode()).hexdigest()[:32]}"


async def parse_query(
    text: str,
    *,
    household: Household,
    members: list[str],
    current_slot: Slot,
) -> ParsedQuery:
    """LLM parse when configured and within budget (cached 24 h), else the rule parser."""
    rule = RuleParser(members)
    if not llm.parse_enabled():
        return rule.parse(text, current_slot)
    kv = get_kv()
    key = _parse_cache_key(household.id, text, members)
    hit = await kv.get(key)
    if hit is not None:
        q = ParsedQuery.model_validate_json(hit)
        return q if q.explicit_slot else q.model_copy(update={"slot": current_slot})
    if not await take_budget(household.id, local_day(household)):
        return rule.parse(text, current_slot)
    s = get_settings()
    try:
        q = await LlmParser(
            llm.get_llm_client(), s.MAHARAJ_PARSE_MODEL, s.MAHARAJ_PARSE_TIMEOUT
        ).parse(text, rule, current_slot)
    except Exception as exc:  # timeout, API error, refusal, bad shape: never an error reply
        log.warning("maharaj_parse_fallback", error=type(exc).__name__)
        return rule.parse(text, current_slot)
    await kv.set(key, q.model_dump_json(), s.MAHARAJ_PARSE_CACHE_SECONDS)
    return q


# ---- retrieve + rank -----------------------------------------------------------------------


async def active_members(db: AsyncSession, household_id: uuid.UUID) -> list[Member]:
    stmt = (
        select(Member)
        .where(Member.household_id == household_id, Member.archived_at.is_(None))
        .order_by(Member.created_at, Member.id)
    )
    return list((await db.execute(stmt)).scalars())


def published_stmt() -> Select[tuple[Recipe]]:
    return (
        select(Recipe)
        .where(Recipe.status == RecipeStatus.published)
        .options(selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient))
    )


async def published(db: AsyncSession) -> list[Recipe]:
    return list((await db.execute(published_stmt())).scalars())


@dataclass(slots=True)
class Turn:
    message: ChatMessage
    items: list[Ranked]
    recipes: dict[str, Recipe]
    needs_write: bool


def resolve_lang(q: ParsedQuery, user: User) -> Lang:
    if q.language is not None:
        return q.language
    return user.locale if user.locale in ("en", "hi", "hinglish") else "hinglish"  # type: ignore[return-value]


async def answer(
    db: AsyncSession,
    *,
    session: ChatSession,
    household: Household,
    user: User,
    text: str,
    slot: str | None,
) -> Turn:
    """Runs parse -> retrieve -> rank and stores both messages. The bot text is filled here
    (template) unless the LLM writer will fill it later (``needs_write``)."""
    s = get_settings()
    t0 = time.perf_counter()
    current = chat_slot(slot or session.slot)
    cfg = await load_config(db)
    members = await active_members(db, household.id)
    names = [m.name for m in members]
    user_at = utcnow()
    db.add(
        ChatMessage(
            session_id=session.id,
            author=ChatAuthor.user,
            text=text,
            slot=current,
            created_at=user_at,
        )
    )

    # Release the database connection while the LLM parses (up to 2.5 s): the user message
    # is stored now; nothing below needs this transaction (review M4).
    await db.commit()
    q = await parse_query(text, household=household, members=names, current_slot=current)
    t_parse = time.perf_counter()

    snap = await catalogue_cache.published(db)
    by_id = snap.by_id
    eaters = [eater_view(m, day=local_day(household)) for m in members]
    if q.off_topic:
        result = Retrieval(items=[], slot=q.slot, exact_count=0, n_eaters=len(eaters))
    else:
        from app.services import learning

        score_ctx = await learning.score_context(db, household, local_day(household))
        result = retrieve(
            snap.views,
            eaters,
            q,
            ctx=score_ctx,
            min_results=s.MAHARAJ_MIN_RESULTS,
            limit=s.MAHARAJ_MAX_CARDS,
            tiebreak={str(r.id): r.slug for r in snap.recipes},
        )
    t_rank = time.perf_counter()

    lang = resolve_lang(q, user)
    facts = build_facts(
        q=q,
        lang=lang,
        slot=result.slot,
        slot_label_hinglish=slot_label_from(cfg, result.slot),
        n=len(result.items),
        all_ok=result.all_ok,
        exact_count=result.exact_count,
        dropped_groups=result.dropped,
        eaters=eaters,
        recipe_names=[by_id[x.recipe.id].name for x in result.items],
        query_text=text,
        typed_members=RuleParser(names).typed_members(text),
    )
    template = TemplateWriter().write(facts)
    needs_write = (
        not q.off_topic
        and bool(result.items)
        and llm.write_enabled()
        and await budget_left(household.id, local_day(household)) > 0
    )
    latency = {
        "parse": round((t_parse - t0) * 1000, 1),
        "retrieve": round(result.retrieve_ms, 1),
        "rank": round(result.rank_ms, 1),
        "write": None if needs_write else round((time.perf_counter() - t_rank) * 1000, 1),
    }
    bot = ChatMessage(
        session_id=session.id,
        author=ChatAuthor.bot,
        text=None if needs_write else template,
        parsed_filters={
            "query": q.model_dump(mode="json"),
            "dropped": result.dropped,
            "reply": facts.as_dict(),
            "template_text": template,
        },
        recipe_ids=[x.recipe.id for x in result.items],
        chips=follow_ups(cfg, result.slot),
        slot=result.slot,
        latency_ms=latency,
        status=ChatMessageStatus.pending if needs_write else ChatMessageStatus.complete,
        # Strictly after the user message so history ordering is stable.
        created_at=max(utcnow(), user_at + timedelta(milliseconds=1)),
    )
    db.add(bot)
    now = utcnow()
    session.slot = result.slot
    session.last_active_at = now
    session.expires_at = now + timedelta(minutes=s.CHAT_IDLE_MINUTES)
    await db.flush()
    log.info(
        "maharaj_reply",
        household_id=str(household.id),
        parse_source=q.source,
        cards=len(result.items),
        exact=result.exact_count,
        dropped=result.dropped,
        async_write=needs_write,
        latency_ms=latency,
    )
    return Turn(message=bot, items=result.items, recipes=by_id, needs_write=needs_write)


# ---- write (async half) --------------------------------------------------------------------


async def complete_write(message_id: uuid.UUID | str) -> str | None:
    """Fill a pending bot message: LLM writer within budget, else the stored template."""
    mid = uuid.UUID(str(message_id))
    s = get_settings()
    async with get_sessionmaker()() as db:
        msg = await db.get(ChatMessage, mid)
        if msg is None or msg.status != ChatMessageStatus.pending:
            return None
        session = await db.get(ChatSession, msg.session_id)
        household = await db.get(Household, session.household_id) if session else None
        data = msg.parsed_filters or {}
        template = str(data.get("template_text") or "")
        t0 = time.perf_counter()
        text: str | None = None
        status = ChatMessageStatus.complete
        client = llm.get_llm_client()
        if (
            household is not None
            and client is not None
            and llm.write_enabled()
            and await take_budget(household.id, local_day(household))
        ):
            facts = ReplyFacts.from_dict(data.get("reply") or {})
            names = [r.name for r in (await catalogue_cache.published(db)).recipes]
            # Release the connection during the LLM call (up to 3 s, review M4).
            await db.commit()
            try:
                text = await LlmWriter(
                    client, s.MAHARAJ_WRITE_MODEL, s.MAHARAJ_WRITE_TIMEOUT
                ).write(facts, names)
            except Exception as exc:  # timeout / API error: template, never an error
                log.warning("maharaj_write_fallback", error=type(exc).__name__)
        source = "llm" if text else "template"
        msg.text = text or template
        msg.status = status
        msg.latency_ms = {
            **(msg.latency_ms or {}),
            "write": round((time.perf_counter() - t0) * 1000, 1),
        }
        msg.parsed_filters = {**data, "write_source": source}
        await db.commit()
        log.info("maharaj_write", message_id=str(mid), source=source, latency_ms=msg.latency_ms)
        return msg.text


async def mark_failed(message_id: uuid.UUID | str) -> None:
    """Last resort (e.g. the job crashed): show the template and mark the message failed."""
    async with get_sessionmaker()() as db:
        msg = await db.get(ChatMessage, uuid.UUID(str(message_id)))
        if msg is not None and msg.status == ChatMessageStatus.pending:
            msg.text = str((msg.parsed_filters or {}).get("template_text") or "")
            msg.status = ChatMessageStatus.failed
            await db.commit()


async def enqueue_write(message_id: uuid.UUID, add_background: Any) -> str:
    """ARQ when Redis is real (worker ``maharaj_write``), else an in-process background task
    (``add_background`` = BackgroundTasks.add_task). Returns the mode used."""
    from app.core import queue

    s = get_settings()
    use_arq = s.MAHARAJ_WRITE_MODE == "arq" or (
        s.MAHARAJ_WRITE_MODE == "auto" and queue.queue_enabled()
    )
    if use_arq and await queue.enqueue("maharaj_write", str(message_id)):
        return "arq"
    add_background(_write_or_fail, message_id)
    return "background"


async def _write_or_fail(message_id: uuid.UUID) -> None:
    try:
        await complete_write(message_id)
    except Exception:
        log.exception("maharaj_write_crashed", message_id=str(message_id))
        await mark_failed(message_id)


# ---- retention -----------------------------------------------------------------------------


async def purge_idle_sessions(db: AsyncSession, now: datetime | None = None) -> int:
    """F-5.4-01: hard-delete sessions idle for more than CHAT_RETENTION_DAYS (with messages)."""
    cutoff = (now or utcnow()) - timedelta(days=get_settings().CHAT_RETENTION_DAYS)
    old = select(ChatSession.id).where(ChatSession.last_active_at < cutoff)
    ids = list((await db.execute(old)).scalars())
    if not ids:
        return 0
    await db.execute(delete(ChatMessage).where(ChatMessage.session_id.in_(ids)))
    await db.execute(delete(ChatSession).where(ChatSession.id.in_(ids)))
    return len(ids)
