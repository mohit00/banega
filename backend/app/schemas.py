"""Request/response models (pydantic v2)."""

from __future__ import annotations

import re
import uuid
from datetime import date as date_type
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Any, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    PlainSerializer,
    computed_field,
)

from app.models.enums import (
    Allergen,
    CookKind,
    CookLoginMode,
    Diet,
    IngredientCategory,
    InviteRole,
    MembershipStatus,
    Platform,
    ScalingRule,
    Spice,
    SubscriptionStatus,
)
from app.services import allergens as allergen_svc

# Decimal columns go out as JSON numbers (pydantic's default is a string such as "1.500",
# which mobile clients then have to parse).
WireDecimal = Annotated[Decimal, PlainSerializer(float, return_type=float, when_used="json")]

_PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")


def normalise_phone(value: str) -> str:
    """Accept '98765 43210', '09876543210', '+91 98765-43210'; return E.164 (+91 default)."""
    digits = re.sub(r"[\s\-()]", "", value)
    if digits.startswith("00"):
        digits = "+" + digits[2:]
    if not digits.startswith("+"):
        digits = digits.lstrip("0")
        digits = "+91" + digits if len(digits) == 10 else "+" + digits
    if not _PHONE_RE.match(digits):
        raise ValueError("invalid phone number")
    return digits


def validate_timezone(value: str) -> str:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ValueError("unknown timezone") from exc
    return value


Phone = Annotated[str, AfterValidator(normalise_phone)]
TimeZone = Annotated[str, Field(max_length=64), AfterValidator(validate_timezone)]
Name = Annotated[str, Field(min_length=1, max_length=80)]
Tags = Annotated[list[Annotated[str, Field(max_length=64)]], Field(max_length=50)]


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---- auth -------------------------------------------------------------------------------


class OtpRequestIn(BaseModel):
    phone: Phone
    device_id: str | None = Field(default=None, max_length=128)
    channel: str = Field(default="sms", pattern="^(sms|voice)$")


class OtpRequestOut(BaseModel):
    sent: bool = True
    expires_in: int
    resend_after: int
    dev_code: str | None = None


class OtpVerifyIn(BaseModel):
    phone: Phone
    code: str = Field(min_length=4, max_length=8, pattern=r"^\d+$")
    device_id: str | None = Field(default=None, max_length=128)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    access_expires_at: datetime
    refresh_expires_at: datetime
    user_id: uuid.UUID
    is_new_user: bool = False
    pending_deletion: bool = False


class RefreshIn(BaseModel):
    refresh_token: str


# ---- users / me -------------------------------------------------------------------------


LANGUAGE_TO_LOCALE = {"hi_Latn": "hinglish", "en": "en", "hi": "hi"}
LOCALE_TO_LANGUAGE = {v: k for k, v in LANGUAGE_TO_LOCALE.items()}


class UserOut(ORM):
    id: uuid.UUID
    phone: str
    name: str | None
    locale: str
    created_at: datetime
    deleted_at: datetime | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def language(self) -> str:
        """The app's language code: hi_Latn (Hinglish) | en | hi."""
        return LOCALE_TO_LANGUAGE.get(self.locale, "hi_Latn")


class UserPatch(BaseModel):
    name: Name | None = None
    locale: str | None = Field(default=None, pattern="^(hinglish|en|hi)$")
    # Same setting in the app's codes; wins over ``locale`` when both are sent.
    language: Literal["hi_Latn", "en", "hi"] | None = None


class MembershipOut(ORM):
    household_id: uuid.UUID
    is_admin: bool
    is_member: bool
    member_id: uuid.UUID | None
    cook_id: uuid.UUID | None
    status: MembershipStatus


class MeCookOut(BaseModel):
    id: uuid.UUID
    kind: CookKind
    login_mode: CookLoginMode
    on_duty: bool
    off_duty_until: datetime | None = None


class MeConsentOut(BaseModel):
    version: str | None = None
    accepted_at: datetime | None = None
    current_version: str
    required: bool


class MeOut(BaseModel):
    user: UserOut
    membership: MembershipOut | None
    cook_kind: CookKind | None = None
    # "family" (admin / adult member) and/or "cook" (holds a cook role). A hired cook: ["cook"].
    modes: list[str] = Field(default_factory=list)
    cook: MeCookOut | None = None
    # Phase 7 (F-X-02): DPDP consent status; ``required`` -> show the consent screen.
    consent: MeConsentOut | None = None


# ---- households -------------------------------------------------------------------------


class HouseholdIn(BaseModel):
    name: Name
    timezone: TimeZone = "Asia/Kolkata"
    default_servings: int = Field(default=4, ge=1, le=30)
    enabled_slots: list[str] | None = None
    slot_defaults: dict[str, Any] | None = None
    # Creates the admin's own food profile in the same call.
    admin_member_name: Name | None = None


class HouseholdPatch(BaseModel):
    name: Name | None = None
    timezone: TimeZone | None = None
    default_servings: int | None = Field(default=None, ge=1, le=30)
    enabled_slots: list[str] | None = None
    slot_defaults: dict[str, Any] | None = None
    cook_can_approve_swaps: bool | None = None
    members_can_send_to_cook: bool | None = None
    show_names_to_cook: bool | None = None
    # Phase 6-7 settings. A family cook may change ratings_enabled alone (F-5.10-04).
    auto_decrement: bool | None = None
    ratings_enabled: bool | None = None


class HouseholdOut(ORM):
    id: uuid.UUID
    name: str
    timezone: str
    default_servings: int
    enabled_slots: list[str]
    slot_defaults: dict[str, Any]
    cook_can_approve_swaps: bool
    members_can_send_to_cook: bool
    show_names_to_cook: bool
    auto_decrement: bool = False
    ratings_enabled: bool = True
    created_at: datetime
    deleted_at: datetime | None = None
    # deleted_at + the 7-day undo window (FR-A8); null when not scheduled for deletion.
    undo_until: datetime | None = None


class SubscriptionOut(ORM):
    status: SubscriptionStatus
    product_id: str | None
    trial_ends_at: datetime | None
    renews_at: datetime | None
    store: str | None
    grace_until: datetime | None = None


class HouseholdConsentOut(BaseModel):
    dpdp_accepted_at: datetime
    version: str


class HouseholdMeOut(BaseModel):
    household: HouseholdOut
    membership: MembershipOut
    subscription: SubscriptionOut | None
    # Latest DPDP consent recorded in this household (contract Phase 7).
    consent: HouseholdConsentOut | None = None


class DeletionOut(BaseModel):
    deleted_at: datetime
    undo_until: datetime


# ---- members ----------------------------------------------------------------------------


def _allergen_list(value: object) -> object:
    """Accept "Peanut", "tree nut", "kaju"...; anything off the picklist is a 422 (put it
    in allergens_other instead)."""
    if value is None or not isinstance(value, list | tuple):
        return value
    return allergen_svc.strict(value)


AllergenList = Annotated[list[Allergen], BeforeValidator(_allergen_list), Field(max_length=20)]


def _weekday_set(value: list[int]) -> list[int]:
    return sorted(set(value))


VratDays = Annotated[
    list[Annotated[int, Field(ge=0, le=6)]], Field(max_length=7), AfterValidator(_weekday_set)
]


class MemberBase(BaseModel):
    colour: str | None = Field(default=None, max_length=16)
    is_kid: bool | None = None
    diet: Diet | None = None
    nonveg_exclusions: Tags | None = None
    no_dairy: bool | None = None
    spice: Spice | None = None
    needs: Tags | None = None
    cuisines: Tags | None = None
    # F-5.2-03: picklist only (peanut, tree_nut, milk, gluten, sesame, soy, egg, fish,
    # shellfish, mustard); synonyms are normalised, unknown values are a 422.
    allergens: AllergenList | None = None
    # Anything else: a warning on the profile, never a hard No.
    allergens_other: str | None = Field(default=None, max_length=200)
    dislikes: Tags | None = None
    # Fasting weekdays, 0 = Monday .. 6 = Sunday (vrat rule on those days, household-local).
    vrat_days: VratDays | None = None
    # Health needs shown in the constraint line (never sent to the LLM).
    show_on_home: bool | None = None


class MemberIn(MemberBase):
    name: Name


class MemberPatch(MemberBase):
    name: Name | None = None


class MemberOut(ORM):
    id: uuid.UUID
    household_id: uuid.UUID
    name: str
    colour: str | None
    is_kid: bool
    diet: Diet
    nonveg_exclusions: list[str]
    no_dairy: bool
    spice: Spice
    needs: list[str]
    cuisines: list[str]
    allergens: list[str]
    allergens_other: str | None = None
    dislikes: list[str]
    vrat_days: list[int] = Field(default_factory=list)
    show_on_home: bool = False
    archived_at: datetime | None
    created_at: datetime
    updated_at: datetime


class Page[T](BaseModel):
    items: list[T]
    next_cursor: str | None = None


# ---- invites ----------------------------------------------------------------------------


class InviteIn(BaseModel):
    phone: Phone
    role: InviteRole = InviteRole.member
    member_id: uuid.UUID | None = None


class InviteOut(ORM):
    id: uuid.UUID
    phone: str
    role: InviteRole
    member_id: uuid.UUID | None
    expires_at: datetime
    used_at: datetime | None
    revoked_at: datetime | None
    created_at: datetime


class InviteCreatedOut(InviteOut):
    token: str
    link: str


# ---- devices ----------------------------------------------------------------------------


class DeviceIn(BaseModel):
    platform: Platform
    push_token: str = Field(min_length=8, max_length=512)
    app_version: str | None = Field(default=None, max_length=32)


class DeviceOut(ORM):
    id: uuid.UUID
    platform: Platform
    push_token: str
    app_version: str | None
    created_at: datetime


# ---- catalogue (Phase 2) ----------------------------------------------------------------


class IngredientOut(ORM):
    id: uuid.UUID
    slug: str
    name_en: str
    name_hi: str | None
    aliases: list[str]
    category: IngredientCategory
    allergens: list[str]
    flags: dict[str, Any]
    scaling_rule: ScalingRule
    trackable: bool
    purchase_unit: str | None
    pack_size: WireDecimal | None
    perishable: bool


class StapleOut(ORM):
    id: uuid.UUID
    ingredient: IngredientOut
    low_threshold: WireDecimal | None
    default_pack_qty: WireDecimal | None
    sort_order: int


class ItemsOut[T](BaseModel):
    items: list[T]


class RecipeFlagsOut(BaseModel):
    """Derived from ingredients (F-5.2-01a); never hand-set."""

    is_veg: bool
    has_egg: bool
    has_nonveg: bool
    jain_safe: bool
    no_onion_garlic: bool
    dairy_free: bool
    gluten_free: bool
    allergens: list[str]


class FitOut(BaseModel):
    eater_id: str
    name: str
    status: str  # fit | tweak | no
    reason_key: str
    reason_params: dict[str, Any] = Field(default_factory=dict)


class SummaryOut(BaseModel):
    badge: str  # fit | tweak | no
    label_key: str  # all_perfect | all_with_tweaks | some | no_eaters
    label_params: dict[str, Any] = Field(default_factory=dict)
    note_key: str  # not_for | tweak_for | all_happy
    note_params: dict[str, Any] = Field(default_factory=dict)
    can: int
    perfect: int
    n: int


class RecipeCardOut(BaseModel):
    id: uuid.UUID
    slug: str
    name: str
    name_hi: str | None = None
    sub: str | None = None
    cuisine: str | None = None
    dish_category: str
    meal_slots: list[str]
    mins: int
    spice: int
    tags: list[str]
    colour: str | None = None
    image_url: str | None = None
    mark: str  # veg | egg | non_veg
    flags: RecipeFlagsOut
    summary: SummaryOut | None = None


class ScaledIngredientOut(BaseModel):
    ingredient_id: uuid.UUID
    slug: str
    name_en: str
    name_hi: str | None
    display_text: str | None
    qty: WireDecimal | None
    unit: str | None
    scaled_qty: WireDecimal | None
    scaling_rule: ScalingRule
    is_main: bool
    optional: bool
    trackable: bool
    sort_order: int
    allergens: list[str]


class RecipeDetailOut(RecipeCardOut):
    video_url: str | None = None
    base_servings: int
    servings: int
    scale_factor: float
    # F-5.5-05: above 3x base servings the app shows "Do batch mein banayein".
    batch_suggested: bool
    steps_en: list[str]
    steps_hi: list[str]
    vrat_ok: bool
    ingredients: list[ScaledIngredientOut]
    fits: list[FitOut]
    # F-5.2-03: shown when any eater has allergies ("check packaged ingredients").
    allergy_notice: bool = False


class RecoTileOut(BaseModel):
    recipe: RecipeCardOut
    score: float


class ConstraintOut(BaseModel):
    key: str
    params: dict[str, Any] = Field(default_factory=dict)


class ConstraintLineOut(BaseModel):
    items: list[ConstraintOut]
    more: int = 0


class RecommendationsOut(BaseModel):
    slot: str
    date: date_type
    eater_ids: list[uuid.UUID]
    pick: RecoTileOut | None
    tiles: list[RecoTileOut]
    constraint_line: ConstraintLineOut
    cached: bool = False


# ---- Maharaj chat (Phase 4) -----------------------------------------------------------


class ChatSessionIn(BaseModel):
    slot: str | None = Field(default=None, pattern="^(nashta|lunch|dinner)$")


class ChatWelcomeOut(BaseModel):
    text: str
    chips: list[str]


class ChatSessionOut(BaseModel):
    session_id: uuid.UUID
    slot: str
    reused: bool
    created_at: datetime
    expires_at: datetime
    welcome: ChatWelcomeOut


class ChatMessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    slot: str | None = Field(default=None, pattern="^(nashta|lunch|dinner)$")


class ChatReplyOut(BaseModel):
    """Cards arrive with the 200; ``text`` is null while the LLM writer is still working
    (poll GET /v1/chat/messages/{message_id})."""

    message_id: uuid.UUID
    session_id: uuid.UUID
    # Same RecipeCardOut as /v1/recommendations tiles.
    cards: list[RecipeCardOut]
    slot: str
    chips: list[str]
    text: str | None
    status: str  # pending | complete | failed


class ChatMessageOut(BaseModel):
    id: uuid.UUID
    author: str  # user | bot
    text: str | None
    slot: str | None
    status: str
    recipe_ids: list[str]
    cards: list[RecipeCardOut] = Field(default_factory=list)
    chips: list[str]
    created_at: datetime


class ChatMessageStatusOut(BaseModel):
    message_id: uuid.UUID
    text: str | None
    status: str
