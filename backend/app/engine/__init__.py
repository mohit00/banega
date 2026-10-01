"""Matching engine: pure Python, no I/O. See README.md in this package for the rules."""

from app.engine.ranking import DEFAULT_WEIGHTS, constraint_line, rank, score
from app.engine.rules import fit, summarize
from app.engine.types import (
    Constraint,
    EaterFit,
    EaterView,
    Fit,
    FitStatus,
    Need,
    NonVegExclusion,
    Ranked,
    Ranking,
    RecipeView,
    ScoreContext,
    Summary,
    Weights,
    parse_exclusions,
    parse_needs,
)

__all__ = [
    "DEFAULT_WEIGHTS",
    "Constraint",
    "EaterFit",
    "EaterView",
    "Fit",
    "FitStatus",
    "Need",
    "NonVegExclusion",
    "Ranked",
    "Ranking",
    "RecipeView",
    "ScoreContext",
    "Summary",
    "Weights",
    "constraint_line",
    "fit",
    "parse_exclusions",
    "parse_needs",
    "rank",
    "score",
    "summarize",
]
