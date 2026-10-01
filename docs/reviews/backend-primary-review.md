# Council primary review — backend (Sonnet, 2026-09-26)

Verdict: **needs_changes**. 605/605 tests, ruff and mypy --strict clean. Engine, permission table and ticket state machine are unusually well built and tested.

## Blockers
- **B1 Maharaj LLM write stage leaks every member's name + allergen/health data to the LLM on almost every chat turn (F-7-02).** `services/maharaj/write.py:102-117` `constraint_line(eaters, lang)` iterates all active members and appends "{name} ({allergen} allergy)", "(Jain)", "(low sugar)"; called from `build_facts()` (`:151`) with all members (`pipeline.py:234,252,280`), sent as `family_constraints` to Claude (`write.py:271-291`). This is an ungated reimplementation of `engine/ranking.py` `constraint_line(views, show_health=False)`. `LlmParser` gets it right (`parse.py:646-649`, `typed_members(text)`). Fix: gate the same way or strip names/allergens/diet from LLM facts; keep them only in the template/in-app path; add a test.
- **B2 Admin auth is one shared env credential, no MFA/TOTP, no lockout** (`admin/main.py:43-62`, own TODO at `:10-11`); reachable at `/admin` via nginx (`nginx.conf:61-63`) with all-household PII. Fix: per-staff accounts + TOTP + lockout; until then network-restrict /admin.
- **B3 No audit log; admin deletes are hard SQL deletes bypassing soft-delete/undo** (`admin/main.py:212-217`, `catalogue_admin.py:656-660`, no `can_delete` overrides). Fix: route deletes through service-layer soft delete; audit-log table + hook (staff id, model, pk, before/after).

## Majors
1. Two-households race: `households.py:76-116`, `invites.py:127-176` check-then-act; only unique `(user_id, household_id)` (`household.py:129`). Fix: partial unique `UNIQUE(user_id) WHERE status='active'`.
2. Idempotency "pending" marker has no crash-recovery TTL (`middleware.py:108-113,172-178`) → 409 for 24 h after a kill. Fix: short lease TTL.
3. `REDIS_URL=memory://` not blocked in prod (`config.py:91-98`).
4. F-5.7-12 no-show only alerts on New at due−90 min (`ticket_timers.py:103-133`); no Accepted-not-Cooking branch, per-slot thresholds, household setting, or backup recipient (`notifications.py:258,265` plumbing unused).
5. `LlmWriter.validate()` only blacklists known-but-unshown dishes (`write.py:244-262`); fabricated names pass.
6. App Store webhook has no secret/config guard (`billing.py:86-91` vs Play `:59-68`); `STORE_VERIFIER=fake` allowed in prod; `subscription.py:499-503` trusts `appAccountToken` from unsigned JWS.
7. Allergen picklist not enforced (`enums.py:77-88` unused by `schemas.py`, `models/catalogue.py:76`, `importer.py:202`); "other" can become a silent hard No via `rules.py:44-45`.
8. Allergen matching case-sensitive on the recipe side (`catalogue.py:66` vs `tagging.py:94`/`importer.py:202`).
9. `PLAY_WEBHOOK_SECRET` not checked at boot.
10. No security headers (CSP/X-Frame-Options/HSTS) on /v1 or /admin (`nginx.conf`).
11. No TLS in prod nginx (`nginx.conf:39`, `docker-compose.prod.yml:69-72`).
12. Missing FK indexes: `cooks.member_id/user_id` (0001:137-138), `invites.member_id/created_by` (155,160), `household_memberships.cook_id/member_id` (176-177), `substitution_rules.to_ingredient_id` (0002:144).

## Minors
`ratings_enabled` toggle checks `is_family_cook` inline instead of `can()` (`households.py:130-132`); OTP verify no row lock (`auth.py:139-150`); hourly quota consumed before device-daily check (`auth.py:67-78`); Idempotency-Key never required (`middleware.py:76-78`); `apply_off_duty` ignores Ready (`cooks.py:322-331`); no true concurrent race test; ChatSession no version column; LLM budget consumed on attempt (`pipeline.py:167,353-358`); lazy-singleton ARQ pool race (`pipeline.py:396-420`, `export.py:209-228`); double `summarize()` in retrieve+rank; no index on `Recipe.status`; sublinear scaling below base undocumented; `scale_qty` float round-trip (`catalogue.py:115`); no property test for "other"-allergen; no ANN index on embedding; README says 559 tests; nginx `/admin` prefix without slash; admin upload trusts Content-Type (`catalogue_admin.py:74-76`); `ADMIN_SECRET_KEY` reused for CSRF + session; no `test_config.py`.

## Strengths
One parametrised permission test per §2.1 cell; consistent household scoping (cross-household → 404); declarative STATE_TABLE matching F-5.7-02 row-for-row with every illegal pair tested; off-duty rule all four cases; optimistic concurrency → 409; atomic first-response-wins approvals; UTCDateTime/AwareDatetime everywhere; refresh rotation + reuse detection tested; engine matches its README with an honest parity test; no SQLi/path traversal/N+1 found; all migrations have verified downgrades; compose architecture matches the README.
