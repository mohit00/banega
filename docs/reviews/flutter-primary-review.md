# Council primary review — Flutter app (Sonnet, 2026-09-26)

Verdict: **needs_changes**. Design-token fidelity near pixel-exact; fit engine implements every FRD diet/allergen/vrat fix in order with a 22×5 oracle test; state machine and ladder faithful; deletion+undo, consent and read-only-on-expiry shipped. 211/211 tests, analyze clean (verified).

## Blocker
- **B1 Day-menu draft is one global list, not keyed by (date, slot).** `day_menu.dart:21-43`; written from `home_screen.dart:104`, `chat_screen.dart:396`, `recipe_detail_screen.dart:181`; `plan_controller.dart:97` sync() PUTs the global draft onto whatever (date, slot) is selected (`:124-132`, `plan_screen.dart:109,113`). Switching slot/date sends Lunch dishes to Dinner's menu → wrong ticket to the cook. No tests for setDate/setSlot. Fix: key the draft by (date, slot) or reload from server Menu.dishes on switch and write back only for the active pair.

## Majors
- **M1 MutationQueue.replay() unserialised** (`ticket_cache.dart:267-301`); concurrent today/tomorrow builds + refresh can lose/duplicate queued writes. Fix: single in-flight future / owner Notifier.
- **M2 KitchenError never reads `details.allowed`** (`kitchen_models.dart:168-178`). Fix: fall back to details.allowed.
- **M3 Off-duty backup lookup uses raw onDuty, not `_available(b, due)`** (`demo_kitchen.dart:805` vs `:144`). Fix: use _available.
- **M4 No actor/role enforcement in demo ticket state machine** (`demo_kitchen.dart:479-524`). Fix: thread actor/role through writes.
- **M5 Cook "pause" restarts audio** (`cook_audio.dart:70-78` stop(), `cook_recipe_screen.dart:51-56`). Fix: real pause/resume for audioplayers; document TTS restart.
- **M6 restore() sends the stub token to the real backend** (`billing_adapter.dart:41-54`, `account_providers.dart:162-168` lacks the `available` guard subscribe() has; reachable from `paywall_screen.dart:146`). Fix: restoreToken null until wired + guard.
- **M7 No UI for allergens, dislikes, vrat days, non-veg exclusions, no-dairy; noOnionGarlic/pescatarian diets unreachable** (`members_controller.dart:49-52`, `prefs_screen.dart:197-239`). Fix: add fields + diets to Prefs.
- **M8 No admin vs adult-member identity in demo** (`meIsFamily` always true). Fix: caller-role concept.
- **M9 Five ticket/date-keyed FutureProvider.family without autoDispose that all watch kitchenRevision** (`kitchen_providers.dart:177,183,200,210,216`) → unbounded growth + rebuild storm. Fix: .autoDispose.
- **M10 app_en.arb is Hinglish for 222/528 keys** incl. Splash/Family/Prefs; en-US test asserts only 'Language'. Fix: translate; widen test.
- **M11 No in-flight/double-tap guard** (`cook_ui.dart`, `ticket_detail_screen.dart` chips, `ladder_sheet.dart`, `plan_screen.dart` send/share). Fix: in-flight set per id.
- **M12 Jain root-veg rule has no content-level check**; no seed recipe sets rootVeg. Fix: integrity test on jain==true recipes vs root-veg word list.

## Minors
PhaseStubScreen + stubComingSoon dead (delete); Ready state blocked from notes-only edit (`ticket_detail_screen.dart:90`); no client-side permission hiding on ticket chips; `_patch()` detects dish change by length only; off-duty reassignment silent after confirm; QueuedMutation drops `note` (`ticket_cache.dart:195-243`); markItemOut idempotency optional; health needs in Home header (F-5.3-05); unbounded `_idempotent` cache in demo; `slotForTime` no midnight rollover (`home_providers.dart:11-15`); batch warning at 2× not 3× (intentional, tested); `KitchenTag` missing `large: true` (`ticket_thread_screen.dart:187`); legalTransitions vs cookNextSteps untested overlap; test gaps: setDate/setSlot, replay concurrency, cook_audio, CookRecipeScreen, TicketThreadScreen, double-tap, backup-off-duty, en-US Splash/Home.

Corrected: "full edit reachable during Cooking" claim from a sub-review was checked and is false (inner `editable` gate prevents it).
