"""Phase 6-7 request/response models: stock, ration, the out-of-stock ladder, approvals,
ratings, insights, subscription, consent and export
(docs/contracts/phase6-7-stock-ratings-billing.md)."""

from __future__ import annotations

import uuid
from datetime import date as date_type
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field

from app.schemas import RecipeCardOut, SummaryOut
from app.schemas_kitchen import TicketOut

Level = Literal["in", "low", "out"]
PantryGroup = Literal["sabzi", "dairy", "dal", "anaaj", "masale", "tel_ghee", "dry_fruits", "other"]


class UserRefOut(BaseModel):
    id: uuid.UUID
    name: str


# ---- stock ----------------------------------------------------------------------------------


class StockItemOut(BaseModel):
    ingredient_id: uuid.UUID
    name: str
    name_hi: str | None = None
    # App pantry group; the catalogue category is ``ingredient_category``.
    category: PantryGroup
    ingredient_category: str
    level: Level
    qty: float | None = None
    unit: str | None = None
    low_threshold: float | None = None
    perishable: bool = False
    updated_at: datetime | None = None
    updated_by: UserRefOut | None = None


class StockPut(BaseModel):
    level: Level
    # Omit to keep; null clears.
    qty: Annotated[float, Field(ge=0, le=100000)] | None = None
    unit: Annotated[str, Field(max_length=16)] | None = None


class StockBulkItem(BaseModel):
    ingredient_id: uuid.UUID
    level: Level


class StockBulkIn(BaseModel):
    items: Annotated[list[StockBulkItem], Field(min_length=1, max_length=300)]


# ---- ration ---------------------------------------------------------------------------------

RationStatusLit = Literal["pending", "approved", "rejected", "bought"]


class RationItemIn(BaseModel):
    """``ingredient_id`` or free text ``name`` (matched by alias, else kept as text)."""

    ingredient_id: uuid.UUID | None = None
    name: Annotated[str, Field(max_length=120)] | None = None
    qty: Annotated[float, Field(gt=0, le=100000)] | None = None
    unit: Annotated[str, Field(max_length=16)] | None = None
    note: Annotated[str, Field(max_length=200)] | None = None


class RationRequestIn(BaseModel):
    ticket_id: uuid.UUID | None = None
    # Empty -> 409 ration_empty.
    items: Annotated[list[RationItemIn], Field(max_length=100)]
    note: Annotated[str, Field(max_length=500)] | None = None


class RationItemOut(BaseModel):
    ingredient_id: uuid.UUID | None = None
    name: str
    qty: float | None = None
    unit: str | None = None
    note: str | None = None


class RationRequestOut(BaseModel):
    id: uuid.UUID
    ticket_id: uuid.UUID | None = None
    items: list[RationItemOut]
    status: RationStatusLit
    raised_by: UserRefOut | None = None
    # F-2-04 self-raise by an admin / family cook: note / decision_note carry "self_approved".
    auto_approved: bool = False
    decided_by: UserRefOut | None = None
    decided_at: datetime | None = None
    note: str | None = None
    decision_note: str | None = None
    bought_at: datetime | None = None
    created_at: datetime


class DecisionIn(BaseModel):
    decision: Literal["approved", "rejected"]
    note: Annotated[str, Field(max_length=500)] | None = None


class NeededForOut(BaseModel):
    ticket_id: uuid.UUID
    date: date_type
    slot: str


class RationSuggestionOut(BaseModel):
    ingredient_id: uuid.UUID
    name: str
    name_hi: str | None = None
    level: Level
    unit: str | None = None
    # Empty = low/out in the pantry but not needed by a ticket in the window.
    needed_for: list[NeededForOut]


# ---- ladder ---------------------------------------------------------------------------------


class IngredientRefOut(BaseModel):
    ingredient_id: uuid.UUID
    name: str
    name_hi: str | None = None


class SkipOptionOut(BaseModel):
    type: Literal["skip"] = "skip"
    ingredient: IngredientRefOut
    # True: optional in the recipe, a "can be left out" rule, or onion/garlic with a Jain /
    # no-onion-garlic eater at the table -> no approval needed. False -> 422 skip_not_allowed.
    ok: bool
    reason: Literal["optional", "rule", "jain", "not_used", "required"]
    note_hi: str | None = None


class SwapOptionOut(BaseModel):
    type: Literal["swap"] = "swap"
    substitute_ingredient_id: uuid.UUID
    name: str
    name_hi: str | None = None
    ratio: float
    note_hi: str | None = None
    note_en: str | None = None
    stock: Literal["in", "low", "out", "untracked"]
    # The dish summary for this meal's eaters with the substitute (engine re-check).
    fit_after: SummaryOut | None = None


class LadderOptionsOut(BaseModel):
    save_dish: SkipOptionOut
    swap: list[SwapOptionOut]
    change_dish: list[RecipeCardOut]


class LadderOut(BaseModel):
    """All three steps in one response; ``step`` is the first applicable one."""

    step: Literal["save_dish", "swap", "change_dish"]
    ingredient: IngredientRefOut
    options: LadderOptionsOut
    issue_id: uuid.UUID
    # The dish change_dish would replace.
    replaces_recipe_id: uuid.UUID | None = None


class TicketLadderOut(TicketOut):
    ladder: LadderOut


class ResolveIn(BaseModel):
    """Idempotency-Key supported (POST)."""

    action: Literal["skip", "swap", "change_dish"]
    substitute_ingredient_id: uuid.UUID | None = None
    recipe_id: uuid.UUID | None = None
    # Which open issue (defaults to the latest open one on the ticket).
    ingredient_id: uuid.UUID | None = None


class ApprovalOut(BaseModel):
    id: uuid.UUID
    ticket_id: uuid.UUID | None = None
    ration_request_id: uuid.UUID | None = None
    type: Literal["swap", "change_dish", "ration"]
    status: Literal["pending", "approved", "rejected", "expired"]
    requested_by: UserRefOut | None = None
    decided_by: UserRefOut | None = None
    decision: Literal["approved", "rejected", "expired"] | None = None
    # Human line, e.g. "Dahi -> Doodh".
    detail: str
    decided_at: datetime | None = None
    auto: bool
    expires_at: datetime | None = None
    payload: dict[str, Any]
    created_at: datetime


class ApprovalDecideIn(BaseModel):
    decision: Literal["approved", "rejected"]


# ---- ratings --------------------------------------------------------------------------------


class RatingIn(BaseModel):
    recipe_id: uuid.UUID
    member_id: uuid.UUID
    # 1 bura | 2 theek | 3 bahut accha
    score: Annotated[int, Field(ge=1, le=3)]
    note: Annotated[str, Field(max_length=500)] | None = None


class RatingsIn(BaseModel):
    ratings: Annotated[list[RatingIn], Field(min_length=1, max_length=60)]


class RatingOut(BaseModel):
    id: uuid.UUID
    ticket_id: uuid.UUID
    recipe_id: uuid.UUID
    # Null (and a generic name) when the caller may not see who rated (F-5.10-01).
    member_id: uuid.UUID | None = None
    member_name: str
    rated_by_user_id: uuid.UUID | None = None
    score: int
    note: str | None = None
    created_at: datetime


class TicketRatingsOut(BaseModel):
    ticket_id: uuid.UUID
    rated_at: datetime | None = None
    ratings: list[RatingOut]


class MemberAvgOut(BaseModel):
    member_id: uuid.UUID
    name: str | None = None
    average: float
    count: int


class RatingSummaryOut(BaseModel):
    recipe_id: uuid.UUID
    name: str
    average: float
    count: int
    members: list[MemberAvgOut]
    notes: list[str]


# ---- insights -------------------------------------------------------------------------------


class TopDishOut(BaseModel):
    recipe_id: uuid.UUID
    name: str
    # Times served in the window (same as ``served``).
    count: int
    avg: float | None = None
    ratings: int
    served: int


class CoverageStatsOut(BaseModel):
    meals: int
    fully_covered: int
    pct: float | None = None


class OnTimeOut(BaseModel):
    completed: int
    on_time: int
    pct: float | None = None


class WeeklyInsightsOut(BaseModel):
    # Flat fields the app reads (0-100; 0 when there were no completed meals).
    meals_cooked: int
    on_time_pct: float
    coverage_pct: float
    from_date: date_type
    to_date: date_type
    tickets: int
    completed: int
    cancelled: int
    top_dishes: list[TopDishOut]
    coverage: CoverageStatsOut
    on_time: OnTimeOut
    stock_issues: int


# ---- subscription, consent, export -----------------------------------------------------------


class SubscriptionStateOut(BaseModel):
    status: Literal["trial", "active", "grace", "expired"]
    trial_ends_at: datetime | None = None
    renews_at: datetime | None = None
    grace_until: datetime | None = None
    product_id: str | None = None
    store: str | None = None
    read_only: bool
    # Days until the trial / grace ends (null when active or expired).
    days_left: int | None = None


class RestoreIn(BaseModel):
    # "appstore" and "app_store" are the same store.
    store: Literal["play", "app_store", "appstore"]
    receipt: Annotated[str, Field(max_length=20000)] | None = None
    purchase_token: Annotated[str, Field(max_length=512)] | None = None
    product_id: Annotated[str, Field(max_length=128)] | None = None


class ConsentIn(BaseModel):
    version: Annotated[str, Field(min_length=1, max_length=32)]


class ConsentOut(BaseModel):
    version: str | None = None
    accepted_at: datetime | None = None
    current_version: str
    # True when the caller must (re)accept the current notice.
    required: bool


class ExportJobOut(BaseModel):
    id: uuid.UUID
    status: Literal["pending", "done", "failed"]
    created_at: datetime
    finished_at: datetime | None = None
    download_url: str | None = None
