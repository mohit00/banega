"""Phase 5 request/response models: menus, tickets, cooks, inbox, notification prefs
(docs/contracts/phase5-menus-tickets.md)."""

from __future__ import annotations

import uuid
from datetime import date as date_type
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import AwareDatetime, BaseModel, Field

from app.models.enums import CookKind, CookLoginMode, TicketStatus
from app.schemas import Name, RecipeDetailOut, SummaryOut

GuestDiet = Literal["veg", "jain", "non_veg"]


class Guests(BaseModel):
    adults: int = Field(default=0, ge=0, le=50)
    kids: int = Field(default=0, ge=0, le=50)
    diet: GuestDiet | None = None


class EaterRef(BaseModel):
    member_id: uuid.UUID
    name: str
    colour: str | None = None
    is_kid: bool = False


class DishSwapOut(BaseModel):
    """An applied out-of-stock ladder change on one dish (Phase 6). ``to_*`` null = skipped."""

    from_ingredient_id: uuid.UUID
    from_name: str | None = None
    to_ingredient_id: uuid.UUID | None = None
    to_name: str | None = None
    ratio: float | None = None
    note_hi: str | None = None


class MenuDishOut(BaseModel):
    recipe_id: uuid.UUID
    name: str
    colour: str | None = None
    image_url: str | None = None
    mins: int
    # The RecipeCard summary for this meal's eaters (+ guests).
    summary: SummaryOut | None = None
    # Tickets only: swaps / skips applied by the out-of-stock ladder.
    swaps: list[DishSwapOut] = Field(default_factory=list)


class AssigneeOut(BaseModel):
    cook_id: uuid.UUID
    name: str
    kind: CookKind


class CoverageOut(BaseModel):
    all_covered: bool
    uncovered: list[str]


class RequiredItemOut(BaseModel):
    ingredient_id: uuid.UUID
    display_text: str
    status: Literal["in", "low", "out", "untracked"]


class MenuOut(BaseModel):
    id: uuid.UUID
    date: date_type
    slot: str
    dishes: list[MenuDishOut]
    eaters: list[EaterRef]
    guests: Guests
    servings: float
    due_at: datetime
    assignee: AssigneeOut | None
    coverage: CoverageOut
    required_items: list[RequiredItemOut]
    ticket_id: uuid.UUID | None
    notes: str | None = None
    version: int


class MenuDishesIn(BaseModel):
    recipe_ids: Annotated[list[uuid.UUID], Field(max_length=12)]


class MenuPatch(BaseModel):
    eaters: Annotated[list[uuid.UUID], Field(max_length=30)] | None = None
    guests: Guests | None = None
    due_at: AwareDatetime | None = None
    # Explicit null = no assignee (the ticket starts Unassigned).
    assignee_cook_id: uuid.UUID | None = None
    notes: Annotated[str, Field(max_length=500)] | None = None
    # Override of the computed adult-equivalent servings.
    servings: Annotated[float, Field(gt=0, le=60)] | None = None


class ShareTextOut(BaseModel):
    text: str


class ChangeBy(BaseModel):
    user_id: uuid.UUID | None
    name: str


class ChangeLogEntry(BaseModel):
    at: datetime
    by: ChangeBy
    action: str
    detail: dict[str, Any]


class IssueApprovalOut(BaseModel):
    id: uuid.UUID
    action: Literal["skip", "swap", "change_dish"] | None = None
    type: Literal["swap", "change_dish", "ration"]
    decision: Literal["approved", "rejected", "expired"] | None = None
    auto: bool
    expires_at: datetime | None = None


class StockIssueOut(BaseModel):
    id: uuid.UUID
    ingredient_id: uuid.UUID
    name: str
    step: Literal["save_dish", "swap", "change_dish"]
    resolution: Literal["skip", "swap", "change_dish"] | None = None
    substitute_ingredient_id: uuid.UUID | None = None
    new_recipe_id: uuid.UUID | None = None
    approval: IssueApprovalOut | None = None
    detail: str = ""
    created_at: datetime
    resolved_at: datetime | None = None


class TicketStockIssueCardOut(BaseModel):
    """The app's single stock-issue card on a ticket (latest open issue, else latest)."""

    ingredient_id: uuid.UUID
    name: str
    state: Literal["open", "pending_approval", "timed_out", "resolved"]
    action: Literal["skip", "swap", "change_dish"] | None = None
    approval_id: uuid.UUID | None = None
    expires_at: datetime | None = None
    detail: str = ""


class TicketOut(BaseModel):
    id: uuid.UUID
    menu_id: uuid.UUID | None
    date: date_type
    slot: str
    due_at: datetime
    status: TicketStatus
    assignee: AssigneeOut | None
    dishes: list[MenuDishOut]
    eaters: list[EaterRef]
    guests: Guests
    servings: float
    notes: str | None
    stock_issue_open: bool
    # Phase 6: every item marked Out on this ticket and how the ladder resolved it.
    stock_issues: list[StockIssueOut] = Field(default_factory=list)
    stock_issue: TicketStockIssueCardOut | None = None
    required_items: list[RequiredItemOut]
    updated: bool
    accepted_at: datetime | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None
    completed_by: uuid.UUID | None = None
    rated_at: datetime | None = None
    cancel_reason: str | None = None
    confirmed_by: uuid.UUID | None = None
    # Statuses the caller may move this ticket to via POST .../transitions.
    allowed_next: list[TicketStatus]
    change_log: list[ChangeLogEntry]
    version: int


class ConfirmOut(BaseModel):
    ticket: TicketOut
    share_text: str


class TransitionIn(BaseModel):
    to: TicketStatus
    reason: Annotated[str, Field(max_length=200)] | None = None
    note: Annotated[str, Field(max_length=500)] | None = None
    # unassigned -> new|accepted (admin reassign): who takes it.
    assignee_cook_id: uuid.UUID | None = None


class TicketPatch(BaseModel):
    dishes: Annotated[list[uuid.UUID], Field(max_length=12)] | None = None
    eaters: Annotated[list[uuid.UUID], Field(max_length=30)] | None = None
    guests: Guests | None = None
    servings: Annotated[float, Field(gt=0, le=60)] | None = None
    due_at: AwareDatetime | None = None
    notes: Annotated[str, Field(max_length=500)] | None = None


class MessageIn(BaseModel):
    text: Annotated[str, Field(min_length=1, max_length=1000)]


class MessageAuthor(BaseModel):
    user_id: uuid.UUID | None
    name: str
    role: Literal["family", "cook"]


class MessageOut(BaseModel):
    id: uuid.UUID
    text: str
    author: MessageAuthor
    created_at: datetime


class AudioOut(BaseModel):
    # TTS URLs per Hindi step; null -> the app reads the step with on-device TTS.
    steps_hi: list[str | None]


class TicketRecipeOut(RecipeDetailOut):
    audio: AudioOut


# ---- cooks ---------------------------------------------------------------------------------


class CookOut(BaseModel):
    id: uuid.UUID
    name: str
    kind: CookKind
    member_id: uuid.UUID | None = None
    user_id: uuid.UUID | None = None
    login_mode: CookLoginMode
    is_primary: bool
    is_backup: bool
    on_duty: bool
    off_duty_until: datetime | None = None
    phone_masked: str | None = None


class CookIn(BaseModel):
    kind: CookKind
    member_id: uuid.UUID | None = None
    # Normalised by the handler: a bad number is 422 ``invalid_phone``.
    phone: Annotated[str, Field(max_length=32)] | None = None
    name: Name | None = None
    login_mode: CookLoginMode | None = None


class CookPatch(BaseModel):
    is_primary: bool | None = None
    is_backup: bool | None = None
    on_duty: bool | None = None
    off_duty_until: AwareDatetime | None = None
    # FR-K8 optional reason: chhutti | beemar | bahar | ...
    reason: Annotated[str, Field(max_length=40)] | None = None
    name: Name | None = None
    login_mode: CookLoginMode | None = None


class DutyEntryOut(BaseModel):
    at: datetime
    on_duty: bool
    until: datetime | None = None
    reason: str | None = None
    by: uuid.UUID | None = None


# ---- inbox, prefs, me ----------------------------------------------------------------------


class InboxItemOut(BaseModel):
    id: uuid.UUID
    event: str
    title: str
    body: str
    ticket_id: uuid.UUID | None = None
    # Phase 6-7 deep links.
    approval_id: uuid.UUID | None = None
    ration_request_id: uuid.UUID | None = None
    link: str | None = None
    read_at: datetime | None = None
    created_at: datetime


class NotificationPrefOut(BaseModel):
    event: str
    enabled: bool
    mandatory: bool


class QuietHours(BaseModel):
    start: Annotated[str, Field(pattern=r"^\d{2}:\d{2}$")]
    end: Annotated[str, Field(pattern=r"^\d{2}:\d{2}$")]


class NotificationPrefsOut(BaseModel):
    prefs: list[NotificationPrefOut]
    quiet_hours: QuietHours | None = None


class NotificationPrefIn(BaseModel):
    event: str
    enabled: bool


class NotificationPrefsIn(BaseModel):
    prefs: list[NotificationPrefIn] = Field(default_factory=list)
    # Omit to keep; null to clear.
    quiet_hours: QuietHours | None = None
