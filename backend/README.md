# Banega API (backend)

FastAPI + SQLAlchemy 2 (async) + Alembic + ARQ. Package import name: `app`.

```
backend/
  app/
    main.py            FastAPI app, /v1 prefix, middleware, error handlers
    core/              config (pydantic-settings), db, security (JWT), errors, kv (Redis or
                       in-memory), middleware (request id, Idempotency-Key), logging
    models/            SQLAlchemy models (Phase 1 schema; catalogue.py = Phase 2 catalogue;
                       kitchen.py = Phase 5 menus, tickets, events, messages, inbox, duty log;
                       pantry.py = Phase 6 stock, ration, approvals, ticket stock issues;
                       feedback.py = Phase 7 ratings, served history, consent, export jobs)
    permissions.py     can(actor, action, resource): the §2.1 table (FRD review F-2-02)
    api/               routers: auth, households, members, invites, me, devices,
                       catalogue (recipes, ingredients, staples, config), recommendations,
                       chat (Maharaj), menus, tickets, cooks, inbox, stock (+ ration),
                       approvals, feedback (ratings summary, insights), billing
                       (subscription, webhooks, consent, export)
    engine/            matching engine: fit / summarize / score / rank (pure, see its README)
    services/          otp, tagging (derived diet flags + Jain policy), importer (seed),
                       catalogue (engine views, scaling), publishing, csv_io (admin CSV),
                       maharaj/ (chat: parse, retrieve, write, pipeline), menus, tickets
                       (state table), cooks (duty, off-duty rule), notifications (matrix,
                       inbox, push adapters), ticket_timers (worker sweeps), demo,
                       stock, ration, ladder (out-of-stock), ratings, learning (engine
                       context), insights, subscription, export, refs
    cli.py             `python -m app.cli seed | import-recipes | demo-day | openapi`
    workers/worker.py  ARQ worker (purge after 7-day undo, chat retention, Maharaj write job,
                       ticket/duty timers and kitchen sweeps every 5 min, export job)
  migrations/          Alembic (async env): 0001_initial, 0002_catalogue (+ pgvector), 0003_chat,
                       0004_kitchen, 0005_pantry, 0006_feedback, 0007_purge_tombstone,
                       0008_staff_audit, 0009_constraints, 0010_hardening
  tests/               pytest, SQLite in memory by default; TEST_DATABASE_URL = Postgres
```

## Run locally (no Docker)

From the repo root (Git Bash on Windows, or any POSIX shell):

```bash
scripts/dev.sh setup     # creates backend/.venv, installs backend[dev] + admin deps
scripts/dev.sh test      # 693 tests (SQLite in memory)
scripts/dev.sh lint      # ruff + ruff format --check + mypy --strict
scripts/test-postgres.sh # alembic round trip + the same suite on Postgres (see Phase 8)
```

Run the API against a local Postgres and Redis:

```bash
cd backend
export DATABASE_URL=postgresql+asyncpg://banega:banega@localhost:5432/banega
export REDIS_URL=redis://localhost:6379/0
.venv/Scripts/python -m alembic upgrade head        # .venv/bin/python on macOS/Linux
.venv/Scripts/python -m uvicorn app.main:app --reload --port 8000
```

Load the catalogue and the demo household (idempotent; safe on every deploy):

```bash
.venv/Scripts/python -m app.cli seed                  # publishes recipes without violations
.venv/Scripts/python -m app.cli demo-day              # today's lunch menu + ticket (Phase 5)
.venv/Scripts/python -m app.cli seed --publish all    # dev demo: all 22 prototype recipes
.venv/Scripts/python -m app.cli seed --no-demo        # catalogue only
# in Docker: docker compose -f infra/docker-compose.yml exec api python -m app.cli seed
```

The full catalogue comes from the recipe master sheet (`content/recipes-master.csv`, 1,000
recipes; column guide in `content/templates/recipe-sheet-guide.html`). Import it after `seed`:

```bash
.venv/Scripts/python -m app.cli import-recipes ../content/recipes-master.csv --publish clean --supersede-same-name
```

`--publish clean` publishes only rows that match every ingredient and pass the Jain/diet policy
check; the rest land as drafts and are listed. `--supersede-same-name` moves older published
recipes with the same name (the 22 prototype copies) back to draft. Unknown ingredient names
must first be added to `content/ingredients.seed.json` (then re-run `seed`). `example.com`
image links import as "no photo"; `dry_sabzi` / `bread` read as `sabzi` / `roti_paratha`.

It reads `content/ingredients.seed.json` (286 ingredients), `recipes.seed.json` (the 22
prototype recipes), `app-config.seed.json` and `demo-household.seed.json` ("Purohit Parivaar",
dev admin phone `+919999999999`, 5 members, and two cooks: "Ramesh ji", hired, primary, on
duty, phone `+919999999990` (log in with that number to see cook mode), and Mummy as the
family backup cook, profile-only so the admin runs her tickets). Set `CONTENT_DIR` to read
them from elsewhere.
Four prototype recipes fail the Jain policy check and stay unpublished by default: cheela,
lauki and curd rice contain fresh ginger (a root vegetable) although the prototype marked them
Jain; paneer butter masala as listed has no onion/garlic but is not marked Jain.

Export the OpenAPI spec (used to generate the Flutter client):

```bash
.venv/Scripts/python -m app.cli openapi > ../docs/openapi.json
```

For a quick try without Postgres or Redis:
`DATABASE_URL=sqlite+aiosqlite:///./dev.db REDIS_URL=memory://`. Create the tables with
`alembic upgrade head`, which also runs on SQLite.

OpenAPI docs: http://localhost:8000/v1/docs (dev only). Spec: `/v1/openapi.json`.

## Run in Docker

```bash
cp infra/.env.example infra/.env
docker compose -f infra/docker-compose.yml up --build
# API through nginx: http://localhost:8080/v1/health    Admin: http://localhost:8080/admin
```

`migrate` is a one-shot `alembic upgrade head` job. `api`, `worker` and `admin` wait until it
exits successfully. In dev, `backend/` is bind-mounted and uvicorn and arq reload on changes.
For prod, add `-f infra/docker-compose.prod.yml`. This removes the bind mounts, sets restart
policies, requires secrets and adds a daily `pg_dump`.

## Configuration

| Var | Default | Notes |
|---|---|---|
| `ENV` | `dev` | `dev`/`test` return the OTP code in the `/auth/otp` response |
| `DATABASE_URL` | postgres on localhost | `sqlite+aiosqlite://` works for tests |
| `REDIS_URL` | `redis://localhost:6379/0` | empty or `memory://` = in-process store |
| `JWT_SECRET` | dev value | at least 32 chars; must be changed in staging/prod (enforced) |
| `OTP_PROVIDER` | `dev` | `msg91` / `twilio` are stubs (TODO) and `dev` is refused in prod |
| `ANTHROPIC_API_KEY` | empty | empty = Maharaj runs on the rule parser + template replies only |
| `MAHARAJ_PARSE_MODEL` / `MAHARAJ_WRITE_MODEL` | `claude-sonnet-5` | any Claude model id |
| `MAHARAJ_DAILY_BUDGET` | `200` | LLM calls (parse + write) per household per local day |
| `MAHARAJ_MIN_RESULTS` | `3` | relax soft filters while fewer cards match (1 = prototype behaviour) |
| `PUSH_PROVIDER` | `noop` | `noop` logs pushes; `fcm` is a stub until FCM credentials are wired (TODO) |
| `TICKET_NOT_CONFIRMED_AFTER_MINUTES` / `TICKET_NOT_CONFIRMED_CLOSE_HOURS` | `180` / `24` | worker timers |
| `TICKET_NO_SHOW_BEFORE_MINUTES` / `TOMORROW_NOTIFY_LOCAL_TIME` | `90` / `20:00` | worker timers |
| `TRIAL_DAYS` | `7` | server-side trial from household creation (F-3-03) |
| `STORE_VERIFIER` | `auto` | `auto` = fake store + unverified App Store JWS in dev/test, real adapters elsewhere (TODO: they refuse with 503 until wired); `fake` / `store` force one |
| `PLAY_WEBHOOK_SECRET` | empty | Play RTDN secret, `X-Webhook-Secret` header only (never `?token=`) |
| `PLAY_PUBSUB_AUDIENCE` / `PLAY_PUBSUB_SERVICE_ACCOUNT` | empty | alternative: verify the Pub/Sub push OIDC token (Google JWKS, audience, service account) |
| `APPSTORE_BUNDLE_ID` / `APPSTORE_ENVIRONMENT` | empty / `Production` | checked in every signed App Store notification |
| `APPSTORE_ROOT_CERT_PATH` | bundled `app/certs/AppleRootCA-G3.cer` | the x5c chain must end in this root |
| `APPSTORE_ISSUER_ID` / `APPSTORE_KEY_ID` / `APPSTORE_PRIVATE_KEY` | empty | App Store Server API credentials (required outside dev/test) |
| `OTP_HMAC_KEY` / `INVITE_HMAC_KEY` | empty | separate hash keys; empty = derived from `JWT_SECRET` (old hashes keep verifying) |
| `OTP_MAX_PER_IP_PER_HOUR` / `OTP_MAX_GLOBAL_PER_MINUTE` | `20` / `300` | SMS pumping guard (plus per number / per device) |
| `OTP_LOCK_MAX_SECONDS` | `21600` | cap of the doubling wrong-code lock |
| `TRUSTED_PROXIES` | loopback + private ranges | peers whose `X-Forwarded-For` is honoured |
| `IDEMPOTENCY_LEASE_SECONDS` / `REFRESH_GRACE_SECONDS` | `30` / `60` | pending-key lease; parallel-refresh window |
| `ALLOW_NOOP_PUSH` | `0` | outside dev/test `PUSH_PROVIDER=noop` refuses to boot unless set (staging) |
| `TICKET_AT_RISK_BEFORE_MINUTES` / `TICKET_ALERT_LOOKBACK_HOURS` / `TICKET_STUCK_CANCEL_HOURS` | `45` / `6` / `24` | worker alert timers (per-slot overrides in `slot_defaults`) |
| `WORKER_BATCH_SIZE` / `WORKER_JOB_TIMEOUT_SECONDS` | `200` / `240` | sweep batch; explicit ARQ job timeout |
| `CATALOGUE_CACHE_SECONDS` | `60` | published-catalogue snapshot re-check interval |
| `EXPORT_TTL_DAYS` | `7` | data exports (files + rows) are deleted after this |
| `CONSENT_VERSION` | `2026-09` | DPDP notice version the app must post to `/v1/consent` |
| `MEDIA_DIR` | `media` | data exports go to `MEDIA_DIR/exports/{household}/` (nginx returns 404 for `/media/exports/`) |

Access tokens last 15 minutes. Refresh tokens last 90 days and rotate on every use; if an old
refresh token is used again, the whole session is revoked.

## API conventions (Phase 1)

- Every error has the shape `{code, message_en, message_hi, details}`.
- Requests are scoped to the caller's household. An id from another household returns 404.
- Creating `POST`s accept `Idempotency-Key`. A replay returns the stored response with the
  header `Idempotent-Replayed: true`. Reusing a key with a different body returns 422.
- Every response carries `X-Request-ID` (the incoming value is echoed back), and logs are JSON.
- List endpoints use cursor pagination (`?cursor=&limit=`).

| Endpoint | Notes |
|---|---|
| `POST /v1/auth/otp` | 5 per number per hour, 10 per device per day, 20 per IP per hour, 300 per minute overall, 30 s resend; 3 wrong codes burn the code and lock this phone on this device / IP (10 min, doubling) |
| `POST /v1/auth/verify` | returns the token pair and creates the user on first login |
| `POST /v1/auth/refresh` · `/logout` · `/logout-all` | the previous refresh token returns the same new pair for 60 s |
| `POST /v1/households` | creates the household, the admin membership and a 14-day trial |
| `GET/PATCH /v1/households/me` | PATCH needs `edit_household` |
| `DELETE /v1/household` · `POST /v1/household/restore` | 7-day undo window |
| `GET/POST /v1/members`, `GET/PATCH/DELETE /v1/members/{id}` | DELETE archives the member |
| `GET/POST /v1/invites`, `DELETE /v1/invites/{id}` | admin only; bound to a phone, 7 days, single use |
| `POST /v1/invites/{token}/accept` | the OTP-verified phone must match the invite |
| `GET/PATCH/DELETE /v1/me`, `POST /v1/me/restore` | account deletion with a 7-day undo |
| `POST /v1/devices`, `DELETE /v1/devices/{id}` | registers push tokens |

## Catalogue and recommendations (Phases 2-3)

Recipes, ingredients and config are global; each recipe response is computed for the
caller's household (active members, or `?eaters=id,id` from that household; foreign ids 404).

| Endpoint | Notes |
|---|---|
| `GET /v1/recipes?slot=&q=&eaters=&cursor=&limit=` | published only, A-Z, each with the household badge (`summary`) |
| `GET /v1/recipes/{id}?servings=N&eaters=` | per-eater `fits`, `summary`, scaled ingredients (linear; sublinear = ×1.5 per doubling; fixed), `batch_suggested` above 3× base ("Do batch mein banayein", quantities then null) |
| `GET /v1/recommendations?slot=&date=&eaters=&show_health=` | engine only: `pick`, 8 `tiles` (max 2 per dish category, pick excluded), `constraint_line`; cached 60 s per household + request hash (Redis, in-memory fallback); needs `edit_day_menu` |
| `GET /v1/ingredients?q=&cursor=` | matches English/Hindi names, slug and Hinglish aliases |
| `GET /v1/staples` · `GET /v1/config` | pantry-tracked ingredients; admin-editable app config |

Diet flags on a recipe (`is_veg`, `has_egg`, `has_nonveg`, `jain_safe`, `no_onion_garlic`,
`dairy_free`, `gluten_free`, `allergens`) are derived from its ingredients on every save
(`services/tagging.py`, F-5.2-01a) and are read-only in the admin. The editor's claims
(`editorial_jain_safe`, `editorial_diet`) are checked against them; contradictions go to
`policy_violations`, which block publishing. The engine's rule order, reason keys and score
formula are documented in `app/engine/README.md`.

## Maharaj chat (Phase 4)

`app/services/maharaj/`: parse -> retrieve -> rank -> write, every stage with a fallback so a
slow or failing LLM never produces an error reply.

| Stage | What | Fallback |
|---|---|---|
| Parse | `LlmParser`: Claude, JSON-schema structured output (`ParsedQuery`: slot, tags, max_mins, ingredients include/exclude, cuisines, member_focus, guests, diet, spice, mood, language, off_topic), 2.5 s timeout, no retries, cached 24 h per household + normalised text | `RuleParser`: the prototype's reply() regexes plus Devanagari, Hinglish spelling variants, negations ("paneer nahi", "bina pyaaz"), explicit minutes, guests |
| Retrieve + rank | hard filters (allergen No for any eater, member_focus No, exclusions, stated diet, a named slot) never relax; soft filters relax in order ingredients -> cuisine -> tags -> max_mins (+15, then off) while fewer than `MAHARAJ_MIN_RESULTS` match; exact matches stay first; engine score (F-6-05), ties on minutes then slug; top 4 | - |
| Write | `LlmWriter`: Claude, max 2 sentences, only listed dishes, no health claims, post-validated (F-7-04), 3 s timeout | `TemplateWriter`: the prototype's texts exactly (Hinglish), plus English and Devanagari |

Temperature: current Claude models (Sonnet 5, Opus 4.7+) reject sampling parameters, so parse
determinism comes from the schema; the FRD's temperature 0 / 0.3 is sent only to older models
that accept it (`app/services/maharaj/llm.py`). Thinking is off and effort `low` on both calls.
The LLM sees the user's text as quoted data and member names only when the user typed them
(F-7-02).

| Endpoint | Notes |
|---|---|
| `POST /v1/chat/sessions {slot?}` | `{session_id, slot, reused, welcome: {text, chips}}`; reuses the caller's session idle < 30 min with the same slot |
| `GET /v1/chat/sessions/{id}/messages?cursor=&limit=` | oldest first; bot messages carry `cards` |
| `POST /v1/chat/sessions/{id}/messages {text, slot?}` | 200 `{message_id, cards, slot, chips, text, status}`. With an LLM writer: `text: null, status: pending`, the write runs in the ARQ worker (`maharaj_write`) or, with `REDIS_URL=memory://`, a background task. Without: template text inline. 410 on an expired session, 429 over 30 messages / user / 10 min |
| `GET /v1/chat/messages/{id}` | `{message_id, text, status}` for polling the pending text |

Cards are `RecipeCardOut`, the same schema as `/v1/recommendations` tiles. Sessions are per
user and private (F-5.4-01): other users, including the admin, get 404; a hired cook gets 403
(`ask_maharaj`). The worker deletes sessions idle for 30 days (`purge_chat_sessions`, daily).
Each reply logs `maharaj_reply` with `latency_ms` per stage (parse, retrieve, rank, write),
also stored on the message.

The golden set is `content/golden-queries.json` (112 queries: Hinglish, English, Devanagari,
spelling variants, seeded from the prototype's quick asks, chips, ticker and follow-ups).
`tests/test_maharaj_parse.py` requires >= 95% (the rule parser is at 100%). The admin shows
it with the live accuracy and a download under "Maharaj golden set".

Not built yet: pgvector similarity (`retrieve.embed()` is a no-op until an embedding provider
is configured; retrieval is keyword + filters), multi-turn context (FR-C5, last 6 turns),
streaming the write, voice input.

## Menus, tickets, cooks, notifications (Phase 5)

Contract: `docs/contracts/phase5-menus-tickets.md`. FRD review rules implemented: eaters,
guests and servings (F-5.6-01), due time (F-5.7-01), the ticket state table (F-5.7-02), the
off-duty rule (F-5.7-06), no-show (F-5.7-12), one hired cook and the phone collision rule
(F-2-05, F-2-06), open tickets on cook removal (F-2-07, F-5.7-10), self-approval (F-2-04), the
notification matrix (F-X-01).

- **Menu** (`services/menus.py`): one per (date, slot). Eaters default to all active members,
  then to the last choice for the same slot and weekday (`Household.eater_defaults`). Servings
  are adult-equivalents (adult 1.0, kid 0.5, guests the same) and can be overridden. Coverage:
  every eater has at least one dish that is not "no"; guests are one virtual eater with the
  guest diet or the strictest eater diet. Due time defaults: nashta 08:30, lunch 13:30, dinner
  20:30, tiffin 07:30, shaam 17:30 (`slot_defaults[slot].due` overrides). The assignee is
  pre-filled with the primary cook. `required_items` come from the recipes; the status is
  `in` for staples and `untracked` otherwise until Phase 6 plugs pantry levels into the
  `StockLookup` protocol.
- **Ticket** (`services/tickets.py`): `STATE_TABLE` is the only place status changes are
  defined (rows: from, to, actor roles, entry point, condition). An illegal pair for the
  caller is 409 `{code: "invalid_transition", allowed: [...]}` (`allowed` also in `details`);
  a legal pair for another role is 403. Every action appends a `TicketEvent` (`change_log`).
  Confirm creates the ticket: hired assignee -> `new`; family cook or the confirmer herself ->
  `accepted` (self-approved); no assignee -> `unassigned`; assignee off duty at `due_at` -> the
  on-duty backup, else `unassigned`. Confirming a menu whose ticket is still open is 409
  `menu_already_confirmed`; later changes are `PATCH /tickets/{id}` (FR-K7: before Cooking any
  field; a hired-cook ticket goes back to `new` with `updated=true`; a family-cook ticket stays
  `accepted` with `updated=true`; during Cooking/Ready only `notes`; closed tickets never).
  Claim is a version-guarded update: first wins, the second gets 409 `already_claimed`.
- **Versioning**: `Menu.version` and `Ticket.version` bump by one per write and guard the
  UPDATE (SQLAlchemy `version_id_col`). An `If-Match: <version>` mismatch (bare number; `"7"`
  and `W/"7"` are accepted too) is 412 `version_mismatch`; a lost race is 409
  `version_conflict`.
- **Cooks** (`services/cooks.py`): one hired cook per household (409 `hired_cook_limit`); a
  hired-cook phone in one household only (409 `phone_in_other_household`). A hired cook added
  by phone gets cook mode on first OTP login (`link_pending_cook`). A family cook is linked to
  a member, and to her login if she has one; otherwise `login_mode=via_admin` and the admin
  performs her ticket actions. Primary and backup are exclusive; the first cook becomes
  primary. Off duty (F-5.7-06): cooking stays; new/accepted tickets due in the period go to
  the on-duty backup, else unassigned, and the admin is alerted; nothing moves back on return.
  Delete is soft (`removed_at`): new/accepted tickets go unassigned, and a cook-only login
  loses the household and its sessions.
- **Cook mode**: a hired cook with no family role reaches only `/tickets` (own tickets; the
  list is forced to `mine`), transitions, item out, messages,
  `/tickets/{id}/recipes/{recipe_id}`, `PATCH /cooks/{self}` (duty only), duty history,
  `/inbox`, `/me` and `/devices`. Everything else is 403 with `details.reason = "cook_mode"`
  (allowlist in `api/deps.py`). Recipes in cook mode carry no member fits (F-5.7-05).
- **Notifications** (`services/notifications.py`): `MATRIX` maps event -> roles -> channels.
  `emit()` writes one `InboxItem` per recipient (never the actor) and hands a push to the
  `PushAdapter` (`NoopPush` in dev and tests). Per-event switches and quiet hours
  (`GET/PUT /v1/me/notification-prefs`) suppress push only. Mandatory events (ticket
  created/updated for the assignee, stock issue, "Khaana bana?") cannot be switched off.
  Events beyond the contract: `ticket_cancelled`, `cook_message`, `family_message`,
  `chef_claimed`, `cook_on_duty`.
- **Timers** (`services/ticket_timers.py`, ARQ cron every 5 min): due + 3 h -> `not_confirmed`
  and an admin prompt; 24 h later -> `cancelled` (`auto_closed`); due - 90 min and still `new`
  -> one `no_show` alert; 20:00 household-local -> one `tomorrow_tickets` per assignee; off
  period over -> back on duty. Every sweep takes `now`, so tests use a fake clock.

| Endpoint | Notes |
|---|---|
| `GET /v1/menus?date=&slot=` | a Menu (404 if none); without `slot`, the day's list |
| `PUT /v1/menus/{date}/{slot}/dishes {recipe_ids}` | creates the menu; duplicates ignored; 422 `unknown_recipe` |
| `PATCH /v1/menus/{id}` | `eaters, guests, due_at, assignee_cook_id (null = none), notes, servings` |
| `POST /v1/menus/{id}/confirm` | `{ticket, share_text}`; Idempotency-Key, If-Match |
| `GET /v1/menus/{id}/share-text` | `{text}`: WhatsApp-ready Hinglish (dishes, eaters, servings, saaman) |
| `GET /v1/tickets?date=&status=a,b&mine=true` | bare list sorted by `due_at`; `date` is `YYYY-MM-DD`, `today` or `tomorrow`; or `from=&to=` (max 31 days). One of them is required (422 `date_required` / `range_too_long`) |
| `GET/PATCH /v1/tickets/{id}` | Ticket, plus `updated`, `required_items`, `allowed_next`, `cancel_reason`, `confirmed_by` |
| `POST /v1/tickets/{id}/transitions {to, reason?, note?, assignee_cook_id?}` | `assignee_cook_id` for the admin reassigning an `unassigned` ticket |
| `POST /v1/tickets/{id}/claim` | Chef for the day; the claimant gets a family-cook role on first claim |
| `POST /v1/tickets/{id}/items/{ingredient_id}/out` | `stock_issue_open=true`; admin and approvers alerted |
| `GET/POST /v1/tickets/{id}/messages` | `{id, text, author: {user_id, name, role}, created_at}`; role is `family` or `cook` |
| `GET /v1/tickets/{id}/recipes/{recipe_id}?servings=` | recipe detail scaled to the ticket (servings rounded up), plus `audio.steps_hi` (nulls) |
| `GET/POST /v1/cooks`, `PATCH/DELETE /v1/cooks/{id}` | admin; a cook patches her own duty |
| `GET /v1/cooks/{id}/duty-history?month=YYYY-MM` | admin or the cook |
| `GET /v1/inbox?cursor=&limit=&unread=` | bare list, newest first; next cursor in `X-Next-Cursor` |
| `POST /v1/inbox/{id}/read` | |
| `GET /v1/me` | adds `modes` (`family`, `cook`) and `cook {id, kind, login_mode, on_duty, off_duty_until}` |
| `GET/PUT /v1/me/notification-prefs` | `{prefs: [{event, enabled, mandatory}], quiet_hours}` |

Admin: Menus, Tickets (change log inline; search by status, slot, date), Cook duty log, Inbox
items, and "Ticket board" (`/admin/ticket-board?date=`: one day's tickets by status).

Not built yet: FCM/APNs delivery (the adapter is a stub), TTS audio URLs, scheduled or
recurring off duty (FR-K9), and the "Badlav" re-share text for WhatsApp-only cooks. (The
substitution ladder, pantry levels and rating prompts arrived in Phases 6-7, below.)

## Stock, ration, out-of-stock ladder (Phase 6)

Contract: `docs/contracts/phase6-7-stock-ratings-billing.md` (shapes adjusted to the Flutter
client where noted). FRD review rules: F-5.8-01/02, F-5.6-04, F-5.8-04, F-5.9-01/06, F-2-02/04.

- **Pantry** (`services/stock.py`): tracked items are the global `Staple` rows. The first
  `GET /v1/stock` materialises one `StockItem` per staple at `in`. `StockItem` is the single
  source of truth: menu and ticket `required_items[].status` read it at render time
  (`in | low | out`, `untracked` without a Staple row). A change to low/out emits `stock_low`
  (admin). `category` is the app's pantry group (`sabzi | dairy | dal | anaaj | masale |
  tel_ghee | dry_fruits | other`); the catalogue category is `ingredient_category`.
- **Ration** (`services/ration.py`): raise (admin, hired cook, family cook); free text is
  matched by alias ("pyaaz" -> Onion) or kept as text with `ingredient_id: null`. An admin or
  family cook raising her own list is auto-approved (F-2-04: `auto_approved`, note
  `self_approved`, an `Approval{type: ration, auto: true}` for the log). Decide is a guarded
  UPDATE (first answer wins, then 409 `already_decided`); bought requires approved (409
  `not_approved`) and sets tracked items `in`. Suggest: low/out items needed by open tickets
  in the window, then any other low/out item.
- **Ladder** (`services/ladder.py`) on item-out: the pantry level goes `out`, a
  `TicketStockIssue` opens and the response carries `ladder: {step, ingredient, options:
  {save_dish, swap, change_dish}, issue_id, replaces_recipe_id}` (all three steps; `step` =
  first applicable). save_dish = skip when the item is `optional`, a curated "can be left out"
  rule exists (`SubstitutionRule.ratio = 0`, to = from), or it is onion/garlic with a Jain /
  no-onion-garlic eater at the table. swap = `SubstitutionRule` only, dropped when the
  substitute is out, and re-checked by the engine for every eater and the guests: any new No
  (allergen, diet, dislike) removes it; `fit_after` is the dish summary with the substitute.
  change_dish = top 3 published recipes for the slot whose tracked ingredients are in/low,
  never an allergen No, ranked with the learning context.
- **Resolve / approvals**: `POST /tickets/{id}/stock-issue/resolve {action,
  substitute_ingredient_id?|recipe_id?, ingredient_id?}` creates an `Approval`. When the caller
  may approve her own action (§2.1: admin, adult member, family cook, hired cook for swaps
  while `cook_can_approve_swaps`), it is `auto` and applied at once; a hired cook's dish change
  always waits. Pending approvals go to approvers (`approval_request`), first response wins,
  and after 30 minutes the worker marks them `expired`, logs `stock_issue_timeout` and alerts
  the admin; the ticket keeps `stock_issue_open`. A swap rewrites the dish snapshot
  (`dishes[].swaps`, summary = `fit_after`) and `required_items`; a dish change replaces the
  dish and syncs the menu. Ticket `stock_issue` is the app's card (`open | pending_approval |
  timed_out | resolved`), `stock_issues` the full list. Change log actions: `item_out`,
  `approval_requested`, `approval_approved`, `approval_rejected`, `stock_skip`, `stock_swap`,
  `stock_change_dish`, `stock_issue_timeout` (+ `ration_requested`, `ration_bought`,
  `stock_decremented`, `rated`).
- **Auto-decrement** (Should, `Household.auto_decrement=false`): on completed, perishable
  tracked items actually used (after swaps/skips) drop `in -> low` once; never to `out`.

## Ratings, learning, billing, consent, export (Phase 7)

- **Ratings** (`services/ratings.py`): 1 bura | 2 theek | 3 bahut accha, upsert per (ticket,
  recipe, member) on completed tickets only (409 `not_completed`); the first sets `rated_at`.
  Own profile (`rate_meal`) or a profile-only member as proxy (`rate_for_profile_member`);
  otherwise 403 `not_your_rating`. `POST` returns the Ticket; `GET /tickets/{id}/ratings`
  lists them. `Household.ratings_enabled=false` (a family cook may switch it herself) -> 409
  `ratings_disabled` and no prompts. Summary: a hired cook gets the aggregate only unless
  `show_names_to_cook`; an adult member sees her own ratings by name.
- **Completion hook**: `ServedHistory` per dish, auto-decrement, `rate_prompt` to confirmer +
  admin (including the one who completed).
- **Learning** (`services/learning.py`, used by `/recommendations`, Maharaj and the ladder):
  per (member, recipe) average mapped 1..3 -> 1..5 (dislikes from 30 days, likes from 90),
  last served date (3-day repetition penalty), Out tracked ingredients (stock term; unknown
  until the household has pantry rows). Only completed tickets count.
- **Insights**: `GET /v1/insights/weekly?end=` -> `meals_cooked, on_time_pct (completed <=
  due + 15 min), coverage_pct, top_dishes[{recipe_id, name, count, avg}]` + detail; Monday
  10:00 local `weekly_summary` to the admin.
- **Subscription** (`services/subscription.py`): trial 7 days from creation, one per phone
  and device id (a second household starts `expired`). `trial -> active -> grace (renews_at
  + 3 days) -> expired`, applied on read and persisted by the sweep. Restore verifies through
  the store adapter (fake in dev: any token/receipt not starting with "invalid"; product
  `banega_weekly_50`; `appstore` = `app_store`). Webhooks: `/v1/webhooks/play` (Pub/Sub RTDN,
  secret header) and `/v1/webhooks/appstore` (JWS v2, payload decoded without verification in
  dev); stale events are ignored. Expired = read-only (402 `subscription_expired`) for writes to
  menus, chat and ticket edits/claims; transitions, item out, stock issue and messages stay
  open for tickets dated today or tomorrow (household-local). Trial reminders
  (`expiry_reminder`) on day 5 and day 7 at 10:00 local, once each.
- **Consent**: `POST /v1/consent {version}` (must equal `CONSENT_VERSION`), `GET
  /v1/consent`; `GET /v1/me` has `consent {version, accepted_at, current_version, required}`;
  `/v1/households/me` has `consent {dpdp_accepted_at, version}`. Consent given before the
  household exists moves in on creation. Screen texts: `app_config.consent`.
- **Export**: `POST /v1/export` (admin) -> 202 job (one pending job per household: a repeat
  returns it; files and rows expire after 7 days); the worker (inline without Redis) writes
  `MEDIA_DIR/exports/{household}/{job}.json` and an `export_ready` inbox item with `link`;
  `GET /v1/export/{id}` and `/download` (authenticated). Only the requester's own chats.
- **Purge** (worker, after the 7-day undo): chat sessions/messages, ratings, served history,
  stock issues, approvals, ration, stock, inbox, consent, export jobs and files, then the
  household; purged users also lose their chats, consents and inbox.

| Endpoint | Notes |
|---|---|
| `GET /v1/menus/{id}` | one Menu by id (required_items from the pantry) |
| `GET /v1/stock`, `PUT /v1/stock/{ingredient_id}`, `POST /v1/stock/bulk` | update_stock: admin, cooks |
| `POST/GET /v1/ration-requests`, `GET .../suggest?days=`, `POST .../{id}/decide`, `POST .../{id}/bought` | a cook-only login lists her own |
| `POST /v1/tickets/{id}/items/{ingredient_id}/out` | Ticket + `ladder` |
| `POST /v1/tickets/{id}/stock-issue/resolve` | Ticket; 409 `no_stock_issue` / `approval_pending`; 422 `skip_not_allowed` / `invalid_substitute` / `invalid_recipe` |
| `GET /v1/approvals?status=`, `POST /v1/approvals/{id}/decide` | `detail` ("Curd → Milk"), user refs `{id, name}` |
| `POST/GET /v1/tickets/{id}/ratings`, `GET /v1/ratings/summary?recipe_id=` | |
| `GET /v1/insights/weekly` | admin, adult members |
| `GET /v1/subscription`, `POST /v1/subscription/restore` | |
| `POST /v1/webhooks/play`, `POST /v1/webhooks/appstore` | Play: `X-Webhook-Secret` header or Pub/Sub OIDC bearer; App Store: x5c-verified JWS |
| `POST/GET /v1/consent` | login only, no household needed |
| `POST /v1/export`, `GET /v1/export/{id}`, `GET /v1/export/{id}/download` | admin |

Inbox items carry optional `approval_id`, `ration_request_id` and `link`. Cook mode adds
`/stock` (GET, PUT, bulk), own ration requests (+ suggest), stock-issue resolve,
`/ratings/summary` (masked) and `/subscription`.

Admin: Stock items, Ration requests (items inline), Approvals, Ratings, Consents,
Subscriptions (search a status to filter), and "Kitchen health" (`/admin/kitchen-health`:
pending approvals, low/out stock per household, this week's ratings, subscriptions by status).

Seed: `content/substitutions.seed.json` (13 curated rules: dahi -> doodh (+ nimbu), paneer ->
tofu, moongphali -> kaju (allergen-checked), pyaaz -> leave out, lahsun -> hing, ghee -> tel,
maida -> aata, basmati -> chawal, sooji -> poha, hari mirch -> laal mirch, tamatar ->
amchur / imli, malai -> doodh) and demo pantry levels for Purohit Parivaar (dahi and hara
dhaniya out; paneer, tamatar, hari mirch, doodh low). `python -m app.cli demo-day` also marks
dahi Out on today's lunch ticket so the ladder can be demoed (step `swap`: dahi -> doodh).

The OpenAPI file in `docs/` is not regenerated by this phase; refresh it with
`python -m app.cli openapi > docs/openapi.json` (from backend/).

## Hardening (Phase 8, after the Council review)

Findings: `docs/reviews/backend-independent-review.md` (C/H/M/L) and
`docs/reviews/backend-primary-review.md` (B, majors #1-#12). What changed:

**Database and CI**
- Purge (C2): a purged user has `phone = NULL` + `phone_deleted_at` (0007); the old 44-char
  tombstone overflowed `VARCHAR(20)` on Postgres and rolled back every purge.
- Constraints (H5, primary #1, #12; 0009): partial unique indexes for one active membership
  per login, one active hired cook per household, one active cook phone per household;
  unique `subscriptions.purchase_token` / `original_transaction_id`; FK indexes on
  cooks / invites / memberships / substitution rules; `recipes.status`;
  `inbox_items(household_id, event, created_at)`. An `IntegrityError` is a 409 `conflict`
  (a lost race), never a 500. Creating or joining a household releases memberships in
  soft-deleted households; `POST /household/restore` is 409 `already_in_household` when the
  user is active elsewhere; `check_phone_free` ignores soft-deleted households; a cook invite
  re-checks the phone at acceptance.
- Postgres CI (M1): `TEST_DATABASE_URL=postgresql+asyncpg://...` runs the whole suite on
  Postgres (schema from the models once, rows emptied per test). `scripts/test-postgres.sh`
  also runs `alembic upgrade head -> check -> downgrade base -> upgrade head -> check`.
  `.github/workflows/ci.yml`: ruff + mypy, SQLite tests, Postgres (`pgvector/pgvector:pg16`)
  tests with the migration round trip, `docker compose config` (dev + prod) and `build`, and
  an `nginx -t` of the rendered config.

**Production configuration** (C3, primary #3/#6/#9; `tests/test_config.py`)
- Outside `ENV=dev|test` the settings refuse to load (all problems listed at once) with:
  `STORE_VERIFIER=fake`, `REDIS_URL` empty / `memory://`, no Play webhook auth
  (`PLAY_WEBHOOK_SECRET` or the Pub/Sub OIDC pair), the default dev database password, missing
  `APPSTORE_*` credentials, a missing root certificate, `PUSH_PROVIDER=noop` (unless
  `ALLOW_NOOP_PUSH=1`, which warns), a dev `JWT_SECRET`, `OTP_PROVIDER=dev`.
- App Store notifications: `AppleJwsDecoder` (`services/store_jws.py`) verifies the x5c chain
  certificate by certificate to the bundled Apple Root CA - G3 (fingerprint pinned in a
  test), Apple's marker OIDs, validity at `signedDate`, the ES256 signature, bundle id and
  environment. The unverified decoder only exists in dev/test, and `appAccountToken` (a
  household id) is only trusted from a verified payload.
- Play RTDN: `X-Webhook-Secret` header or the Pub/Sub push OIDC token; `?token=` is gone
  (it ended up in access logs). A malformed `notificationType` is ignored, not a 500.
- `/v1/openapi.json` is not served when `ENV=prod`.

**Admin** (B2/B3, H4; `admin/security.py`, `services/staff.py`, 0008)
- Per-staff accounts (`staff_users`): email + argon2id password + TOTP (RFC 6238, each code
  once). First login shows the otpauth URI and key once (`/admin/enroll`); lost it -> another
  staff member resets it (action) or `python -m app.cli staff-reset-totp --email ...`.
  Five failures lock the email for 15 minutes. `python -m app.cli staff-create --email ...`
  (password from `--password`, `STAFF_PASSWORD` or a prompt) prints the URI. The env
  credential works only in dev/test while no staff account exists.
- Every create / edit / delete / action in any admin view writes `audit_log` (staff, action,
  model, pk, before, after; secrets never copied), in the same transaction.
- Deleting a user, household, member or cook in the admin is the service soft delete
  (`deleted_at` + sessions revoked / `archived_at` / `remove_cook`: tickets unassigned);
  ingredients are deactivated (`is_active=False`; `recipe_ingredients` is ON DELETE RESTRICT).
  Users, households, members and cooks cannot be created in the admin.

**nginx** (`infra/nginx/`): `limit_req` on `/v1/auth/` (10/min), `/admin/login` (10/min) and
`/admin/` (20/s); `nosniff`, `Referrer-Policy: no-referrer`, HSTS when the client connection
is HTTPS, `X-Frame-Options: DENY` + `frame-ancestors 'none'` + `no-store` on `/admin/`;
`$uri` (not `$request_uri`) in the access log; `/admin` -> `/admin/`; an incoming
`X-Forwarded-Proto` (load balancer) is passed through; `ADMIN_ALLOW_CIDR` renders
`allow ...; deny all;` into the admin locations (`render.sh`, envsubst);
`tls.conf.example` is a 443 server with certbot notes. The API runs uvicorn without
`--proxy-headers` and resolves the client IP from `X-Forwarded-For` itself (right-most
untrusted hop, `TRUSTED_PROXIES`).

**Auth** (H2, M3): per-IP and global OTP send limits, all checked before any counter is
consumed; a code is burned after 3 wrong guesses (counted on the code, across devices);
the lock is scoped to phone + device (or IP) and doubles on every repeat within a day, so a
stranger cannot lock the owner out; a code is consumed with a compare-and-set UPDATE; a
provider failure is 503 `otp_unavailable`. Refresh: compare-and-set rotation; the previous
refresh token returns the same new pair for 60 s (parallel refreshes on app resume), then a
replay revokes the session. OTP codes and invite tokens have their own HMAC keys.

**Idempotency** (M2, primary #2): only 2xx and 400/404/422 are replayed (409/429/402/401/403/412
run again); `/v1/auth/*` is never cached; the pending marker is a 30 s lease renewed while the
request runs; with Redis down the request runs without replay protection (logged).

**Maharaj** (B1, primary #5): the LLM writer sees `family_constraints` built by
`write.llm_constraints()`: allergies as anonymous counts ("two peanut allergy"), Jain /
no-onion-garlic / mild-spice named only for members the user typed, everyone else counted,
never health needs. The in-app template line hides health needs unless the member has
`show_on_home`. `validate()` also rejects any capitalised, dish-like word that is not on the
shown cards, the meal, the user's text or the facts (fabricated dishes -> template).

**Allergens** (H3, primary #7/#8; 0010): member, ingredient and recipe allergens are
`Allergen` picklist values (synonyms such as "Peanuts", "kaju", "dairy" normalised; the API
answers 422 for anything else; import and admin refuse unknown values). Free text goes to
`Member.allergens_other`: shown as a warning, never a hard No. The engine intersects enum
values only. Existing rows are normalised by the migration.

**Members** (client fields; 0010): `vrat_days` (weekday ints, 0 = Monday) turns on the vrat
rule on those household-local days (recommendations for the requested date, menus for the
menu date, Maharaj today); `show_on_home` shows that member's health needs in the
constraint line (still never sent to the LLM).

**Worker** (H1, M10, primary #4): every sweep (ticket timers, subscriptions, weekly summary)
works in id batches, one ticket / subscription / household per transaction, re-selected with
`FOR UPDATE SKIP LOCKED`; failures are logged, counted (`failed`, kv
`metrics:worker_failures:*`) and never stop the rest. `notification_marks` (unique
household + kind + local date) replaces inbox scans for "kal ke tickets", trial reminders and
the weekly summary. Explicit ARQ `job_timeout` (240 s) and cron timeouts. No-show and at-risk
only look 6 h back (no alerts on history after an outage); no-show also reaches the backup
cook; new: **at_risk** (accepted, not cooking 45 min before due, to admin + assignee);
per-slot thresholds `Household.slot_defaults[slot].no_show_minutes` / `.at_risk_minutes`
(5-360); new / unassigned tickets nobody picked up are cancelled 24 h after due
(`auto_closed`, `not_picked_up_24h`).

**Hot paths and data hygiene** (M4-M9): recommendations and Maharaj use an in-process
catalogue snapshot (recipes + engine views, reloaded when max `updated_at` / count changes,
re-checked at most every 60 s); the chat releases its database connection before the LLM
parse and write. Pushes are queued in `push_outbox` inside the transaction and delivered after
commit (`flush_push_outbox`: kicked by the API / sweeps, plus a 1-minute cron; `SKIP LOCKED`,
5 attempts). `purge_housekeeping` (daily): OTP requests > 1 day, sessions expired or revoked
> 7 days, inbox > 90 days, sent pushes > 7 days, marks > 60 days, exports > 7 days (files
too). The only admin of a live household gets 409 `transfer_admin_first` on `DELETE /v1/me`;
a hired cook deleting her account archives her cook row and unassigns her open tickets.
`PATCH /menus/{id}` refuses a `due_at` on another day (422 `due_at_wrong_day`). Re-binding a
push token to another user is logged. The API image creates `/srv/media` owned by the app
user; compose and image healthchecks use `/v1/health/ready`.

**Launch gates (not done here)**
- OTP delivery: `OTP_PROVIDER=msg91` is still a stub (a send answers 503 `otp_unavailable`);
  wire MSG91 (DLT template, voice fallback). Consider Play Integrity / App Attest on
  `/auth/otp`.
- Store verification: `StoreApiVerifier` still answers 503; implement the Play Developer API
  (`purchases.subscriptionsv2.get`) and the App Store Server API with the `APPSTORE_*` keys.
  Webhook verification itself is done.
- Push: `FcmPush` only logs; add the FCM HTTP v1 client with service-account credentials
  (the outbox and retries are in place).
- TLS: certificates (certbot per `infra/nginx/tls.conf.example`, or a load balancer), then
  set `ADMIN_ALLOW_CIDR`; the admin cookie is Secure-only outside dev.
- Backups off the VM (object storage) and a restore drill; Redis `requirepass` is in the
  prod override (`REDIS_PASSWORD`).

## Migrations

```bash
scripts/dev.sh revision "add tickets"   # autogenerate against DATABASE_URL
scripts/dev.sh migrate                  # compose migrate job (or: migrate --local)
```

`tests/test_migrations.py` runs `alembic upgrade head` on SQLite and checks that the result
matches the models, so a model change without a migration fails CI.
