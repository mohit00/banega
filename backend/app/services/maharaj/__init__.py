"""Maharaj chat pipeline (Phase 4): parse -> retrieve -> rank -> write.

- ``parse``: ``RuleParser`` (the prototype's reply() regexes, extended) and ``LlmParser``
  (Claude, JSON-schema output, 2.5 s timeout, rule fallback).
- ``retrieve``: hard + soft filters over published recipes, engine ranking, soft-filter
  relaxation (F-7-01, F-5.4-04).
- ``write``: ``TemplateWriter`` (the prototype's texts) and ``LlmWriter`` (Claude, 3 s
  timeout, validated, template fallback).
- ``pipeline``: budget, cache, rate limit and the glue used by ``app.api.chat`` and the worker.
"""
