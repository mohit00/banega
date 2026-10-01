# Phase 6 + 7 contract — stock, ration, out-of-stock ladder, ratings, learning, billing, deletion/consent

Builds on docs/contracts/phase5-menus-tickets.md. Household-scoped, permission-checked (§2.1 table).

## Phase 6 — Stock and ration

```
StockItem {ingredient_id, name, name_hi, level: in|low|out, qty?: number, unit?, low_threshold?, updated_at, updated_by}
RationRequest {id, ticket_id?, items: [{ingredient_id, name, qty?, unit?, note?}], status: pending|approved|rejected|bought, raised_by, decided_by?, decided_at?, note?, created_at}
```

- `GET  /v1/stock` → `[StockItem]` (all tracked staples for the household; defaults `in` on first read).
- `PUT  /v1/stock/{ingredient_id}` `{level, qty?}` (permission update_stock: admin, cooks) → StockItem. Level change to `out`/`low` emits `stock_low` to admin per the notification matrix.
- `POST /v1/stock/bulk` `{items: [{ingredient_id, level}]}` → list.
- `GET  /v1/menus/{id}` and `GET /v1/tickets/{id}` now fill `required_items[].status` from stock (in/low/out; untracked if no Staple row).
- `POST /v1/ration-requests` `{ticket_id?, items}` (permission raise_ration) → RationRequest; family-cook/admin self-raise is auto-approved (F-2-04) and logged.
- `GET  /v1/ration-requests?status=` ; `POST /v1/ration-requests/{id}/decide` `{decision: approved|rejected, note?}` (approve_ration); `POST /v1/ration-requests/{id}/bought` (mark_bought) → sets the items' stock level to `in`.
- `GET  /v1/ration-requests/suggest?days=7` (Should) → items needed by tickets in the window that are low/out.
- Auto-decrement (Should, off by default `Household.auto_decrement=false`): on ticket `completed`, perishable tracked items used by the dishes drop `in→low` once.

### Out-of-stock ladder (FRD §5.9), on `POST /v1/tickets/{id}/items/{ingredient_id}/out`
Response adds `ladder: {step, options}` computed by the engine:
1. **save_dish**: `{type: "skip", ingredient, ok: bool}` if the ingredient is `optional` in the recipe → no approval; ticket event.
2. **swap**: `[{substitute_ingredient_id, name, ratio, note_hi, fit_after: summary}]` from SubstitutionRule, re-checked by the engine for every eater (never introduces an allergen or a diet No). Needs approval unless `Household.cook_can_approve_swaps` (default true) and the actor is the cook; family cook self-approves.
3. **change_dish**: `[RecipeCard x3]` alternatives for the same slot using only in/low-stock items, ranked by the engine. Approval per §2.1 (admin or adult member, first response wins; family cook self, admin notified).
- `POST /v1/tickets/{id}/stock-issue/resolve` `{action: skip|swap|change_dish, substitute_ingredient_id?|recipe_id?}` → Ticket (creates an Approval if needed).
- `Approval {id, ticket_id, type: swap|change_dish|ration, requested_by, decided_by?, decision?, decided_at?, auto: bool, expires_at}`; `GET /v1/approvals?status=pending`, `POST /v1/approvals/{id}/decide` `{decision}`. 30-minute timeout → `stock_issue_timeout` alert to admin; ticket stays with `stock_issue_open=true`.
- Every ladder step writes a TicketEvent (change log visible on the ticket).

## Phase 7 — Ratings and learning

```
Rating {id, ticket_id, recipe_id, member_id, rated_by_user_id, score: 1..3 (bura|theek|bahut accha), note?, created_at}
```
- After `completed`, the confirmer and admin get `rate_prompt` (inbox+push) listing each eater; proxy rating allowed for profile-only members (rate_for_profile_member).
- `POST /v1/tickets/{id}/ratings` `{ratings: [{recipe_id, member_id, score, note?}]}` (unique per ticket+recipe+member; upsert) → sets `Ticket.rated_at` on first rating.
- `GET  /v1/ratings/summary?recipe_id=` → per-member average and count; hired cook sees only aggregate unless `Household.show_names_to_cook`.
- `Household.ratings_enabled` (default true; a family cook may turn ratings off from settings; appreciation-first copy).
- Learning signal feeds the engine score: per (member, recipe) average, plus `served_at` history for the 3-day repetition rule and `F6` "not the same dish within 3 days unless asked". Only tickets that reached `completed` count (never `not_confirmed`).
- Weekly summary (Should): `GET /v1/insights/weekly` → top dishes, coverage stats, on-time %.

## Phase 7 — Billing, consent, deletion

- Subscription: server-side trial 7 days from household creation, one per phone + device id; `GET /v1/subscription` → `{status: trial|active|grace|expired, trial_ends_at, renews_at, product_id, store}`; `POST /v1/subscription/restore` `{store, receipt|purchase_token}`; webhooks `POST /v1/webhooks/play` (RTDN) and `POST /v1/webhooks/appstore` (App Store Server Notifications v2) update status within 5 min; grace 3 days with banner; expired → read-only: no new menus/chats/tickets, existing today/tomorrow tickets remain workable by the cook; `expiry_reminder` inbox on day 5 and 7 at 10:00.
- Consent: `Household.consent {dpdp_accepted_at, version}`; `POST /v1/consent` ; first-run consent screen text keys `consent_title`, `consent_body`, `consent_llm_note`.
- Data export: `GET /v1/export` → JSON of the household's data (async job → inbox link).
- Deletion already exists (`DELETE /v1/household`, `DELETE /v1/me`, restore, purge after 7 days); purge must also delete chat sessions, ratings, stock, ration, approvals, inbox.

## Notification matrix additions
stock_low→admin; ration_request→admin (+approvers); ration_decided→raiser; stock_issue→admin+approvers; approval_request→approvers; approval_decided→requester; stock_issue_timeout→admin; rate_prompt→confirmer+admin; expiry_reminder→admin; weekly_summary→admin (Should).
