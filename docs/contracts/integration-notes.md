# Integration notes — observed API shapes on the live server (2026-09-26)

Smoke test run against the API on Postgres (migrations 0001–0006, `app.cli seed --publish all`, `app.cli demo-day`). Everything below is what the server actually returns; the Flutter client must parse these.

- `POST /v1/auth/otp` → `{sent, expires_in: 300, resend_after: 30, dev_code}` (dev_code only in ENV=dev; a second request inside 30 s returns no dev_code).
- `POST /v1/auth/verify` → `{access_token, refresh_token, token_type, access_expires_at, refresh_expires_at, user_id, is_new_user, pending_deletion}`.
- `GET /v1/me` → `{user, membership, modes, cook, cook_kind, consent: {version, accepted_at, current_version, required}}` (household id lives under `membership`).
- `GET /v1/members` → `{items: [...], next_cursor}` (NOT a bare list). Member has diet enum values `veg|jain|no_onion_garlic|eggetarian|pescatarian|non_veg`, spice `kam|medium|teekha`, `needs[]`, `cuisines[]`, `allergens[]`, `dislikes[]`, `nonveg_exclusions[]`, `no_dairy`, `is_kid`.
- `GET /v1/recommendations?slot=` → `{slot, date, eater_ids, pick: {recipe: RecipeCard, summary}, tiles: [{recipe, summary}...], constraint_line}` — pick/tiles wrap the card under `recipe` (the Flutter client expected a flat card; adapt the parser or flatten server-side).
- RecipeCard: `{id, slug, name, name_hi, sub, cuisine, dish_category, meal_slots, mins, spice, tags, colour, image_url, mark: veg|egg|non_veg, flags: {is_veg, has_egg, has_nonveg, jain_safe, no_onion_garlic, dairy_free, ...}, ...}`; summary `{badge, label_key, label_params, note_key, note_params}`.
- `POST /v1/chat/sessions` → `{session_id, slot, reused, created_at, expires_at, welcome: {text, chips}}`.
- `POST /v1/chat/sessions/{id}/messages` → `{message_id, session_id, cards: [RecipeCard (flat, with summary)], slot, chips, text}` — text inline when no LLM key is configured.
- `GET /v1/tickets?date=YYYY-MM-DD` → bare list. Ticket has `due_at` in UTC (`08:00:00Z` = 13:30 IST), `assignee: {cook_id, name, kind}`, `dishes[].summary`, `required_items[{ingredient_id, display_text, status}]`, `version`.
- `POST /v1/tickets/{id}/items/{ingredient_id}/out` (Idempotency-Key, If-Match) → Ticket + `ladder: {step, ingredient: {ingredient_id, name, name_hi}, options: {save_dish: {type, ingredient, ok, reason, note_hi}, swap: [{type, substitute_ingredient_id, name, name_hi, ratio, note_hi, note_en, fit_after}], change_dish: [RecipeCard]}, issue_id, replaces_recipe_id}`.
- `GET /v1/stock` → bare list of `{ingredient_id, name, name_hi, category, ingredient_category, level, qty, unit, low_threshold, perishable, updated_at, updated_by}`.
- `GET /v1/subscription` → `{status, trial_ends_at, renews_at, grace_until, product_id, store, read_only, days_left}`.
- `GET /v1/insights/weekly` → `{meals_cooked, on_time_pct, coverage_pct, from_date, to_date, tickets, completed, cancelled, top_dishes, coverage}`.
- `GET /v1/cooks` → bare list with `phone_masked`.
- `GET /v1/inbox` → bare list; next cursor in `X-Next-Cursor` header.
- Error envelope: `{code, message_en, message_hi, details}`; 401 → `code: unauthorized`.

Local dev server used for the smoke test: `uvicorn app.main:app --port 8765` with `DATABASE_URL=postgresql+asyncpg://banega:banega-dev-password@127.0.0.1:5432/banega`, `REDIS_URL=memory://`, `ENV=dev`, `OTP_PROVIDER=dev`, `CONTENT_DIR=../content`. Android emulator reaches it at `http://10.0.2.2:8765`.

## Live emulator run (2026-09-27)

App on the Pixel 8 emulator with `--dart-define=BANEGA_API_BASE_URL=http://10.0.2.2:8765` against the API on Postgres (migrations to 0010).

Verified: phone + OTP login (dev code shown), Home recommendations with real data, Maharaj chat (session, message, cards with per-member notes).

Mismatches found and fixed in the app:
1. `pick` / `tiles` wrap the card as `{recipe, summary}` and use `mark` for diet. `RecipeCard.fromJson` now accepts both shapes.
2. Data fetched before login got 401 and was never refetched. The API client now rebuilds on sign-in / sign-out, so every provider refetches.
3. Engine label and note keys: server sends `all_with_tweaks {n}`, `some {can, n}`, `not_for {names}`, `tweak_for {name, reason_key, reason_params}`, `all_happy`. Labels accept these alongside the local engine's names.
Also added: `X-Device-Id` header (stable per install) on every request; member `vrat_days` (server 0 = Monday) and `show_on_home`; export is `POST /v1/export`.

Open: follow-up chips come from the server config in Hinglish even when the app is in English. Plan/send-to-cook, cook mode, stock and ration not yet clicked through live.
