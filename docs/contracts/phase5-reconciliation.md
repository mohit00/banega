# Phase 5 reconciliation notes (backend behaviour vs Flutter client)

The backend implemented the Flutter client's 11 interpretations. Items below are backend behaviours the Flutter client must handle; check each during the integration pass.

| # | Backend behaviour | Flutter status |
|---|---|---|
| 1 | 409 `invalid_transition` uses the standard envelope `{code, message_en, message_hi, details:{allowed}}` plus top-level `allowed`. Wrong role on a legal pair → 403 `transition_not_allowed` with `details.allowed`. | Client parses `allowed` top-level or in `detail`; verify `details` (plural) is also read and 403 shows a toast |
| 2 | Confirm: open ticket → 409 `menu_already_confirmed` (`details.ticket_id`); empty menu → 422 `menu_empty`; assignee off duty at due_at → backup first, else unassigned. | Client handles 409; verify 422 `menu_empty` message |
| 3 | New menus pre-fill the primary cook; first cook created becomes primary. | Verify Plan's "Kaun banayega" shows the pre-filled assignee |
| 4 | Admin reassign via `/transitions` to new/accepted needs `assignee_cook_id` in body (422 `assignee_required`). | Client has no reassign UI yet (Unassigned queue not built) |
| 5 | Additive: Menu.notes; Ticket.updated, required_items, allowed_next, cancel_reason, confirmed_by; change_log.by = {user_id, name}; /me.cook has on_duty, off_duty_until; message.author has user_id. | Client tolerant of extra fields; can use `allowed_next` to hide buttons |
| 6 | If-Match bare number, `"7"` or `W/"7"`; mismatch → 412 `version_mismatch` (`details.current_version`); lost race → 409 `version_conflict`; losing claim → 409 `already_claimed`. | Matches client |
| 7 | Lists are bare arrays. GET /tickets accepts `date=today|tomorrow` or a date and comma-separated `status`; hired cook forces `mine`; admin `mine` includes via-admin cooks. Inbox cursor in `X-Next-Cursor`, `?unread=`; read returns the item. | Client sends real dates; fine. Inbox pagination header unused yet |
| 8 | POST messages / cooks → 201; DELETE cooks → 204. | Verify client accepts 201/204 |
| 9 | Cook errors: 422 phone_required, member_required, until_in_past, primary_and_backup; 409 already_cook, already_member. PATCH cooks also accepts reason, name, login_mode. Delete is soft; cooking/ready tickets keep their cook. | Settings cook setup (Phase 7 Flutter) must map these codes |
| 10 | First chef claim grants a lasting family-cook role (modes gains "cook"). | Client has no claim screen yet |
| 11 | Cook mode 403 → `code:"forbidden"`, `details.reason:"cook_mode"`; /recipes, /households/me, /cooks list, menus, claim are 403 for hired cooks; ticket recipe returns fits: [] for hired cooks. | Verify cook mode never calls the forbidden endpoints |
| 12 | Actor is never notified of own action; prefs disable push only; prefs shape `{prefs:[{event, enabled, mandatory}], quiet_hours}`; extra events ticket_cancelled, cook_message, family_message, chef_claimed, cook_on_duty. | Phase 7 Flutter settings must use this prefs shape |
| 13 | Menu edits after confirm do not flow to the ticket; ticket PATCH writes back to the menu. | Matches client (draft is local until sent) |
| 14 | Unknown slot → 422 `invalid_slot`. | n/a |

Backend gaps left for later: real FCM/APNs, TTS audio URLs, accepted-but-not-cooking escalation, 2-hour re-alert, backup as no-show recipient, recurring off-duty schedules, WhatsApp "Badlav" re-share text.
