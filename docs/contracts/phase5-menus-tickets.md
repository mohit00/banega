# Phase 5 contract — day menus, tickets, cook mode, notifications

Both the FastAPI backend and the Flutter app build against this. Household-scoped, permission-checked per the §2.1 table (docs/frd-review.md F-2-02). All times ISO-8601 with offset; dates `YYYY-MM-DD` in household timezone. Slots: `nashta | lunch | dinner | tiffin | shaam`.

## Shared shapes

```
RecipeCard   (as served by /v1/recommendations)
EaterRef     {member_id, name, colour, is_kid}
Guests       {adults: int, kids: int, diet: veg|jain|non_veg|null}
MenuDish     {recipe_id, name, colour, image_url?, mins, summary}
Menu {
  id, date, slot, dishes: [MenuDish], eaters: [EaterRef], guests: Guests,
  servings: number (adult-equivalent; adult 1.0, kid 0.5, guests added),
  due_at, assignee: {cook_id, name, kind: hired|family} | null,
  coverage: {all_covered: bool, uncovered: [name]},
  required_items: [{ingredient_id, display_text, status: in|low|out|untracked}],
  ticket_id | null, version
}
Ticket {
  id, menu_id, date, slot, due_at, status, assignee, dishes: [MenuDish],
  eaters, guests, servings, notes, stock_issue_open: bool,
  accepted_at?, started_at?, completed_at?, completed_by?, rated_at?,
  change_log: [{at, by, action, detail}], version
}
Ticket.status: new | unassigned | accepted | cooking | ready | completed | not_confirmed | cancelled
```

## Menus

- `GET  /v1/menus?date=&slot=` → Menu or 404. `GET /v1/menus?date=` → list of that day's menus.
- `PUT  /v1/menus/{date}/{slot}/dishes` `{recipe_ids: [..]}` → Menu (creates the menu if absent; permission edit_day_menu).
- `PATCH /v1/menus/{id}` `{eaters?: [member_id], guests?, due_at?, assignee_cook_id?, notes?}` → Menu. Eaters default = all active members, remembered per (slot, weekday) in `Household.eater_defaults`.
- `POST /v1/menus/{id}/confirm` (Idempotency-Key, If-Match version; permission confirm_menu) → `{ticket: Ticket, share_text: string}`. Creates the ticket per the state table: assignee hired cook → `new`; family cook or self → `accepted`; no assignee / off duty → `unassigned`. `share_text` is the WhatsApp-ready Hinglish message (menu + saaman list) for the share sheet.
- `GET  /v1/menus/{id}/share-text` → `{text}`.

## Tickets

- `GET /v1/tickets?date=&status=&mine=true` → list (cook mode uses `mine=true`, date=today|tomorrow).
- `GET /v1/tickets/{id}` → Ticket.
- `POST /v1/tickets/{id}/transitions` `{to: status, reason?, note?}` (Idempotency-Key, If-Match) → Ticket, or **409** `{code: "invalid_transition", allowed: [status]}`.
  Legal transitions (docs/frd-review.md F-5.7-02 table): new→accepted (assignee), new|accepted→new "updated" on edit (hired-cook only), accepted→cooking, cooking→ready, cooking|ready→completed (assignee or admin), new|unassigned|accepted→cancelled (admin/confirmer/family cook own), cooking→cancelled (admin, reason required), unassigned→new|accepted (admin reassign or chef claim), accepted|cooking|ready→not_confirmed (system, due_at+3h), not_confirmed→completed|cancelled (admin answers "Khaana bana?").
- `PATCH /v1/tickets/{id}` `{dishes?, eaters?, guests?, servings?, due_at?, notes?}` → Ticket (FR-K7 edit rules; bumps version; hired-cook tickets return to `new` with `updated=true`).
- `POST /v1/tickets/{id}/claim` (Chef for the day; unassigned only; first claim wins) → Ticket.
- `POST /v1/tickets/{id}/items/{ingredient_id}/out` → Ticket with `stock_issue_open=true` and `change_log` entry (Phase 6 wires the substitution ladder).
- `POST /v1/tickets/{id}/messages` `{text}` and `GET .../messages` → simple cook↔family thread (K6).

## Cooks and duty

- `GET  /v1/cooks` → `[{id, name, kind, member_id?, user_id?, login_mode, is_primary, is_backup, on_duty, off_duty_until?, phone_masked}]`.
- `POST /v1/cooks` `{kind, member_id? | phone, name, login_mode}`; one hired cook max per household (409 `hired_cook_limit`); phone in another household → 409 `phone_in_other_household`.
- `PATCH /v1/cooks/{id}` `{is_primary?, is_backup?, on_duty?, off_duty_until?}` → applies the off-duty rule (F-5.7-06): cooking stays; new/accepted with due in period → backup if on duty else unassigned; admin alerted.
- `DELETE /v1/cooks/{id}` → removes role; open tickets → unassigned.
- `GET /v1/cooks/{id}/duty-history?month=` (Should).

## Cook mode (same app, role-gated)

- `GET /v1/me` includes `modes: ["family", "cook"]`, `cook: {id, kind, login_mode}` when the caller holds a cook role.
- `GET /v1/tickets?mine=true&date=today` is the K1 list, sorted by due_at.
- `GET /v1/tickets/{id}/recipes/{recipe_id}?servings=` → same shape as `/v1/recipes/{id}` plus `audio: {steps_hi: [url|null]}` (TTS URLs optional; null → on-device TTS).

## Notifications

- `POST /v1/devices` `{platform, push_token, app_version}` (exists). `GET/PUT /v1/me/notification-prefs`.
- Notification matrix (event → roles → channels push|inbox): ticket_created→assignee; ticket_accepted→confirmer; ticket_updated→assignee; ticket_unassigned→admin; ticket_completed→confirmer+admin; not_confirmed_prompt→admin; cook_off_duty→admin; no_show (due−90 min, still `new`)→admin; stock_issue→admin+approvers; ration_request→admin (Phase 6); tomorrow_tickets (20:00)→assignee.
- `GET /v1/inbox?cursor=` → `[{id, event, title, body, ticket_id?, read_at, created_at}]`, `POST /v1/inbox/{id}/read`. The inbox is the source of truth; push is best effort (FCM/APNs adapters, no-op in dev).

## Worker timers

- `due_at + 3h` and still accepted/cooking/ready → `not_confirmed` + admin prompt.
- `not_confirmed` for 24 h → `cancelled` (no learning, no stock effects).
- `due_at − 90 min` and still `new` → no_show alert to admin (F-5.7-12).
- 20:00 daily → tomorrow's tickets notification to assignees.
- Off-duty period end → nothing moves back (tickets stay with backup).
