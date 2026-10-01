from __future__ import annotations

from enum import StrEnum


class MembershipStatus(StrEnum):
    invited = "invited"
    active = "active"
    removed = "removed"


class Diet(StrEnum):
    veg = "veg"
    jain = "jain"
    no_onion_garlic = "no_onion_garlic"
    eggetarian = "eggetarian"
    pescatarian = "pescatarian"
    non_veg = "non_veg"


class Spice(StrEnum):
    kam = "kam"
    medium = "medium"
    teekha = "teekha"


class CookKind(StrEnum):
    hired = "hired"
    family = "family"


class CookLoginMode(StrEnum):
    own = "own"
    via_admin = "via_admin"


class InviteRole(StrEnum):
    member = "member"
    cook = "cook"


class SubscriptionStatus(StrEnum):
    trial = "trial"
    active = "active"
    grace = "grace"
    expired = "expired"


class Platform(StrEnum):
    android = "android"
    ios = "ios"
    web = "web"


# ---- catalogue (Phase 2) ------------------------------------------------------------------


class IngredientCategory(StrEnum):
    vegetable = "vegetable"
    fruit = "fruit"
    grain = "grain"
    pulse = "pulse"
    dairy = "dairy"
    egg = "egg"
    meat = "meat"
    seafood = "seafood"
    spice = "spice"
    herb = "herb"
    oil_fat = "oil_fat"
    sweetener = "sweetener"
    nut_seed = "nut_seed"
    condiment = "condiment"
    packaged = "packaged"
    other = "other"


class Allergen(StrEnum):
    """Fixed allergen picklist (F-5.2-03)."""

    peanut = "peanut"
    tree_nut = "tree_nut"
    milk = "milk"
    gluten = "gluten"
    sesame = "sesame"
    soy = "soy"
    egg = "egg"
    fish = "fish"
    shellfish = "shellfish"
    mustard = "mustard"


class MeatType(StrEnum):
    none = "none"
    chicken = "chicken"
    mutton = "mutton"
    beef = "beef"
    pork = "pork"
    fish = "fish"
    shellfish = "shellfish"
    other = "other"


class ScalingRule(StrEnum):
    """F-5.5-05: linear; sublinear (x0.75 per doubling); fixed."""

    linear = "linear"
    sublinear = "sublinear"
    fixed = "fixed"


class DishCategory(StrEnum):
    dal = "dal"
    sabzi = "sabzi"
    rice = "rice"
    roti_paratha = "roti_paratha"
    curry = "curry"
    snack = "snack"
    sweet = "sweet"
    breakfast = "breakfast"
    one_pot = "one_pot"
    salad_raita = "salad_raita"
    side = "side"  # chutney, pickle, launji, kadhi-style accompaniments
    other = "other"


class RecipeStatus(StrEnum):
    draft = "draft"
    reviewed = "reviewed"
    published = "published"


class MealSlot(StrEnum):
    nashta = "nashta"
    lunch = "lunch"
    dinner = "dinner"
    tiffin = "tiffin"
    shaam = "shaam"


class ChatAuthor(StrEnum):
    user = "user"
    bot = "bot"


class ChatMessageStatus(StrEnum):
    pending = "pending"
    complete = "complete"
    failed = "failed"


# ---- menus and tickets (Phase 5) -----------------------------------------------------------


class TicketStatus(StrEnum):
    """F-5.7-02: stock issue is a flag and "rated" a timestamp, not states."""

    new = "new"
    unassigned = "unassigned"
    accepted = "accepted"
    cooking = "cooking"
    ready = "ready"
    completed = "completed"
    not_confirmed = "not_confirmed"
    cancelled = "cancelled"


# ---- stock, ration, out-of-stock ladder (Phase 6) ---------------------------------------------


class StockLevel(StrEnum):
    in_ = "in"
    low = "low"
    out = "out"


class RationStatus(StrEnum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    bought = "bought"


class ApprovalType(StrEnum):
    swap = "swap"
    change_dish = "change_dish"
    ration = "ration"


class ApprovalDecision(StrEnum):
    approved = "approved"
    rejected = "rejected"
    # 30-minute timeout with nobody answering (stock_issue_timeout to the admin).
    expired = "expired"


class LadderStep(StrEnum):
    save_dish = "save_dish"
    swap = "swap"
    change_dish = "change_dish"


class IssueResolution(StrEnum):
    skip = "skip"
    swap = "swap"
    change_dish = "change_dish"


# ---- billing, export (Phase 7) --------------------------------------------------------------


class ExportStatus(StrEnum):
    pending = "pending"
    done = "done"
    failed = "failed"
