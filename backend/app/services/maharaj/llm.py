"""Anthropic client holder and per-model request options.

The client is created lazily from ``ANTHROPIC_API_KEY``; with no key the chat runs on the
rule parser and the template writer only. Tests inject a fake with ``set_llm_client``.

Per-model options: both LLM stages are short, latency-bound calls, so thinking is turned off
where the model allows it and effort is ``low``. Current models (Sonnet 5, Opus 4.7+, Opus 5,
Fable) reject ``temperature``; determinism for parse comes from the JSON schema, and the
FRD's "temperature 0 / 0.3" is only sent to older models that still accept sampling params.
"""

from __future__ import annotations

from typing import Any

from app.core.config import get_settings

_client: Any = None
_override: Any = None

# Models that still accept temperature (and take no effort/adaptive-thinking options).
_SAMPLING_MODELS = (
    "claude-haiku-4-5",
    "claude-sonnet-4-6",
    "claude-opus-4-6",
    "claude-sonnet-4-5",
    "claude-opus-4-5",
    "claude-opus-4-1",
    "claude-3",
)
# Models where thinking cannot be disabled: effort is the only control.
_ALWAYS_THINKING = ("claude-opus-5-5", "claude-fable", "claude-mythos")


def model_kwargs(model: str, *, temperature: float) -> dict[str, Any]:
    if model.startswith(_SAMPLING_MODELS):
        return {"extra_body": {"temperature": temperature}}
    if model.startswith(_ALWAYS_THINKING):
        return {"output_config": {"effort": "low"}}
    return {"thinking": {"type": "disabled"}, "output_config": {"effort": "low"}}


def set_llm_client(client: Any) -> None:
    """Tests: inject a fake client (None restores the env-configured one)."""
    global _override
    _override = client


def get_llm_client() -> Any:
    """The configured AsyncAnthropic client, or None when no LLM is configured."""
    global _client
    if _override is not None:
        return _override
    key = get_settings().ANTHROPIC_API_KEY
    if not key:
        return None
    if _client is None:
        from anthropic import AsyncAnthropic

        _client = AsyncAnthropic(api_key=key, max_retries=0)
    return _client


def parse_enabled() -> bool:
    return get_settings().MAHARAJ_LLM_PARSE and get_llm_client() is not None


def write_enabled() -> bool:
    return get_settings().MAHARAJ_LLM_WRITE and get_llm_client() is not None
