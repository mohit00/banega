"""Maharaj chat (Phase 4): per-user private sessions (F-5.4-01), parse -> retrieve -> rank
synchronously, reply text written inline (template) or asynchronously (LLM writer).

Permission: ``ask_maharaj`` (a hired cook gets 403). A session belongs to the user who
created it; anyone else, including the household admin, gets 404.
"""

from __future__ import annotations

import base64
import uuid
from datetime import datetime, timedelta
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, BackgroundTasks, Query
from sqlalchemy import and_, or_, select

from app.api.catalogue import card_out
from app.api.deps import DB, HouseholdContext, HouseholdCtx
from app.core.config import get_settings
from app.core.errors import AppError, Gone, NotFound
from app.core.security import utcnow
from app.engine import summarize
from app.models import ChatMessage, ChatSession, Recipe
from app.permissions import Action
from app.schemas import (
    ChatMessageIn,
    ChatMessageOut,
    ChatMessageStatusOut,
    ChatReplyOut,
    ChatSessionIn,
    ChatSessionOut,
    ChatWelcomeOut,
    Page,
    RecipeCardOut,
)
from app.services.catalogue import default_slot, eater_view, recipe_view
from app.services.maharaj import pipeline

router = APIRouter(prefix="/chat", tags=["chat"])


async def _own_session(db: DB, ctx: HouseholdContext, session_id: uuid.UUID) -> ChatSession:
    ctx.require(Action.ask_maharaj)
    session = await db.get(ChatSession, session_id)
    if (
        session is None
        or session.user_id != ctx.user.id
        or session.household_id != ctx.household.id
    ):
        raise NotFound()
    return session


@router.post("/sessions", response_model=ChatSessionOut)
async def open_session(
    ctx: HouseholdCtx, db: DB, body: ChatSessionIn | None = None
) -> ChatSessionOut:
    """Reuses the caller's session if it was active in the last 30 min and the slot did not
    change (F-5.4-03); otherwise starts a new one."""
    ctx.require(Action.ask_maharaj)
    now = utcnow()
    wanted = body.slot if body else None
    stmt = (
        select(ChatSession)
        .where(
            ChatSession.user_id == ctx.user.id,
            ChatSession.household_id == ctx.household.id,
            ChatSession.expires_at > now,
        )
        .order_by(ChatSession.last_active_at.desc())
        .limit(1)
    )
    session = (await db.execute(stmt)).scalar_one_or_none()
    reused = session is not None and (wanted is None or session.slot == wanted)
    if session is None or not reused:
        local = datetime.now(ZoneInfo(ctx.household.timezone or "Asia/Kolkata"))
        slot = pipeline.chat_slot(wanted or default_slot(local, ctx.household.enabled_slots))
        session = ChatSession(
            household_id=ctx.household.id,
            user_id=ctx.user.id,
            slot=slot,
            created_at=now,
            last_active_at=now,
            expires_at=now + timedelta(minutes=get_settings().CHAT_IDLE_MINUTES),
        )
        db.add(session)
    cfg = await pipeline.load_config(db)
    n = len(await pipeline.active_members(db, ctx.household.id))
    welcome = ChatWelcomeOut(
        text=str(cfg["welcome"]).replace("{n}", str(n)),
        chips=[str(c) for c in cfg.get("welcome_chips") or []],
    )
    await db.commit()
    return ChatSessionOut(
        session_id=session.id,
        slot=session.slot,
        reused=reused,
        created_at=session.created_at,
        expires_at=session.expires_at,
        welcome=welcome,
    )


async def _cards(db: DB, ctx: HouseholdContext, ids: set[str]) -> dict[str, RecipeCardOut]:
    """Cards in the /v1/recommendations shape, badges computed for the current household."""
    if not ids:
        return {}
    uids = [uuid.UUID(i) for i in ids]
    recipes = (await db.execute(pipeline.published_stmt().where(Recipe.id.in_(uids)))).scalars()
    today = pipeline.local_day(ctx.household)
    members = await pipeline.active_members(db, ctx.household.id)
    eaters = [eater_view(m, day=today) for m in members]
    return {str(r.id): card_out(r, summarize(eaters, recipe_view(r))) for r in recipes}


def _encode(m: ChatMessage) -> str:
    return base64.urlsafe_b64encode(f"{m.created_at.isoformat()}|{m.id}".encode()).decode()


def _decode(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        at, mid = base64.urlsafe_b64decode(cursor.encode()).decode().rsplit("|", 1)
        return datetime.fromisoformat(at), uuid.UUID(mid)
    except (ValueError, UnicodeDecodeError) as exc:
        raise AppError("invalid_cursor", "Invalid cursor.", "Cursor galat hai.") from exc


@router.get("/sessions/{session_id}/messages", response_model=Page[ChatMessageOut])
async def list_messages(
    session_id: uuid.UUID,
    ctx: HouseholdCtx,
    db: DB,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> Page[ChatMessageOut]:
    """Oldest first; ``next_cursor`` continues with newer messages."""
    session = await _own_session(db, ctx, session_id)
    stmt = select(ChatMessage).where(ChatMessage.session_id == session.id)
    if cursor:
        at, mid = _decode(cursor)
        stmt = stmt.where(
            or_(
                ChatMessage.created_at > at,
                and_(ChatMessage.created_at == at, ChatMessage.id > mid),
            )
        )
    stmt = stmt.order_by(ChatMessage.created_at, ChatMessage.id).limit(limit + 1)
    rows = list((await db.execute(stmt)).scalars())
    page, more = rows[:limit], len(rows) > limit
    cards = await _cards(db, ctx, {rid for m in page for rid in (m.recipe_ids or [])})
    items = [
        ChatMessageOut(
            id=m.id,
            author=m.author.value,
            text=m.text,
            slot=m.slot,
            status=m.status.value,
            recipe_ids=list(m.recipe_ids or []),
            cards=[cards[r] for r in m.recipe_ids or [] if r in cards],
            chips=list(m.chips or []),
            created_at=m.created_at,
        )
        for m in page
    ]
    return Page[ChatMessageOut](
        items=items, next_cursor=_encode(page[-1]) if more and page else None
    )


@router.post("/sessions/{session_id}/messages", response_model=ChatReplyOut)
async def post_message(
    session_id: uuid.UUID,
    body: ChatMessageIn,
    ctx: HouseholdCtx,
    db: DB,
    background: BackgroundTasks,
) -> ChatReplyOut:
    session = await _own_session(db, ctx, session_id)
    if session.expires_at <= utcnow():
        raise Gone(
            "chat_session_expired",
            "This chat has expired. Start a new one.",
            "Ye chat purani ho gayi. Nayi chat shuru kijiye.",
        )
    await pipeline.check_rate_limit(ctx.user.id)
    turn = await pipeline.answer(
        db,
        session=session,
        household=ctx.household,
        user=ctx.user,
        text=body.text.strip(),
        slot=body.slot,
    )
    await db.commit()
    if turn.needs_write:
        await pipeline.enqueue_write(turn.message.id, background.add_task)
    summaries = {x.recipe.id: x.summary for x in turn.items}
    cards = [card_out(turn.recipes[rid], summaries[rid]) for rid in turn.message.recipe_ids]
    return ChatReplyOut(
        message_id=turn.message.id,
        session_id=session.id,
        cards=cards,
        slot=turn.message.slot or session.slot,
        chips=list(turn.message.chips or []),
        text=turn.message.text,
        status=turn.message.status.value,
    )


@router.get("/messages/{message_id}", response_model=ChatMessageStatusOut)
async def get_message(message_id: uuid.UUID, ctx: HouseholdCtx, db: DB) -> ChatMessageStatusOut:
    ctx.require(Action.ask_maharaj)
    msg = await db.get(ChatMessage, message_id)
    if msg is None:
        raise NotFound()
    await _own_session(db, ctx, msg.session_id)
    await db.refresh(msg)
    return ChatMessageStatusOut(message_id=msg.id, text=msg.text, status=msg.status.value)
