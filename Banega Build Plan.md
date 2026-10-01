# Banega — Build Plan (v1)

Stack: Python + FastAPI backend, Flutter app (iOS + Android), Docker Compose with the database and backend in separate containers, and an internal admin panel for catalogue and user management. Plan only; nothing is built yet.

Companion documents:
- "Banega FRD Review (Council).md" (111 findings: 10 Blockers, 46 Majors). Finding IDs below (F-x-yy) refer to that report.
- "Banega — Aaj khaane mein kya hai – App prototype (Play me).html" — the clickable prototype. It is the source of truth for how the app looks, its copy and its motion (FRD §1). Section 1 below is the audit of it.

---

## 0. Decisions to make before any code (1 week, FRD author + tech lead)

The schema depends on these. Do not start migrations until they are answered.

| # | Decision | Review ref | Recommendation |
|---|---|---|---|
| 1 | Eaters, servings and guests per meal | F-5.6-01, F-5.5-01 | Add "Kaun kha raha hai?" step at confirm; adult 1.0, kid 0.5 |
| 2 | Due time per ticket | F-5.7-01 | Per-slot household defaults, editable at confirm |
| 3 | One permission table + self-approval rule | F-2-02, F-2-04 | Adopt the §2.1 table from the review as-is |
| 4 | Ticket state machine | F-5.7-02 | Adopt the replacement table (Unassigned state, stock_issue flag, Not confirmed outcome) |
| 5 | Off-duty and no-show rules | F-5.7-06, F-5.7-12 | One rule: Cooking stays, New/Accepted go to backup else Unassigned |
| 6 | Diet taxonomy, jain_safe, allergens | F-5.2-01a/b, F-5.2-03 | Derive all flags from ingredient flags; allergen picklist is Must |
| 7 | Ingredient vs Staple split, scaling rules | F-5.8-01, F-5.5-05 | ~600–800 Ingredients, Staple = trackable subset |
| 8 | Hindi steps + TTS, or demote FR-K5 | F-5.7-03 | Machine-translate + native review; on-device TTS with server fallback |
| 9 | v1 cook model | F-2-05, F-2-06 | One hired cook + any family cooks; phone collision blocked |
| 10 | Which feature area becomes Should to get Musts down | §7 of review | Ship stock/ration as Should behind tickets |
| 11 | LLM vendor, region, retention terms | F-7-02 | Claude API; no training on data; 30-day deletion |
| 12 | Recipe content licensing | F-7-06 | Decide "curated from public sources" vs licensed |
| 13 | Which screens the prototype does not cover, and who designs them | F-1-02, §1.6 below | Design cook mode, stock, ration, settings, paywall in the same design language before Phase 5 |

Output: FRD v2 with the 18 "Fix these first" items applied, plus a design file for the missing screens.

---

## 1. The prototype: what the app looks like, and what the build must reproduce

The prototype is a single-phone React page (390 × 844) with eight screens driven by one state object. It is the reference for layout, copy, motion and the fit-badge logic. Everything below was read from the prototype's markup, styles and logic.

### 1.1 Screen inventory (prototype → FRD screen ID → Flutter feature)

| Prototype screen | What it shows | FRD | Flutter feature | Backend behind it |
|---|---|---|---|---|
| Splash | Haldi-yellow page, "banega." wordmark, "AI MAHARAJ" badge, rotating 3D thali with steam and orbiting spices, H1 "Aaj khaane mein kya hai?", CTA "Apna ghar set karo", secondary "Demo family ke saath dekho" | S1 | onboarding/splash | none; demo family is a local sandbox (F-5.1-04) |
| Family (Step 1 of 2) | "Ghar mein kaun kaun hai?", one tile per member (avatar initial, name, diet badge, summary line "Medium mirch · Low sugar · North Indian"), dashed "Member jodo", CTA "{n} log · Aage badho" | S2 | members/list | GET/POST /members |
| Prefs (Step 2 of 2 · PASAND) | Member tab strip, "{name} ki pasand", four sections: "Kya khaate hain?" (Veg / Jain / Egg / Non-veg with hints), "Mirch kitni?" (Kam / Medium / Teekha with chilli icons), "Koi zaroorat ya parhez?" (Low oil, Low sugar, High protein, No maida, Kid-friendly), "Favourite cuisine" (7 cuisines), CTA "Save · {name}" | S3 | members/prefs | PUT /members/{id}; diet list grows per F-5.2-01b, allergen picklist per F-5.2-03 |
| Loading | Thali animation, "Maharaj aapke ghar ko samajh raha hai…", constraint line, progress bar; 1.9 s in prototype, max 3 s per FRD | S5 | home/loading | first GET /recommendations |
| Home | Haldi header with slot eyebrow ("SUBAH KA NASHTA" / "DOPAHAR KA KHAANA" / "RAAT KA KHAANA"), household name "Purohit Parivaar", family line, avatar stack; search bar with rotating ticker of example asks and a mic; slot segmented control (Nashta / Lunch / Dinner); dark-green hero card "MAHARAJ KA PICK" with name, fit label, minutes, "Recipe dekho"; quick-ask chips; "{slot} ke options · sabke hisaab se" 2-column grid of tiles (photo, veg mark, "{n} MIN" badge, name, cuisine, fit badge, ADD/ADDED); sticky "{n} dish · Aaj ka menu … Cook ko bhejo" bar; bottom nav Ghar / Maharaj se pucho (raised yellow chef button) / Parivaar | S4 | home | GET /recommendations?slot&date (engine only) |
| Chat | Haldi header with back, bobbing chef avatar, "Maharaj", "{n} logon ki pasand yaad hai", "Menu · {n}" pill; bot bubbles (white) and user bubbles (black, right); horizontal recipe mini-cards under a bot reply with note + fit badge + ADD; follow-up chips; typing indicator "rotiyaan sek raha hoon…" with flipping rotis; input "Aaj dinner mein kuch halka…", mic, send | S6 | chat | POST /chat (parse → rank → write), cards stream before text |
| Detail | Full-bleed photo with slow Ken Burns, back button, meta line (veg mark · diet label · cuisine · minutes), H1 name, sub line, fit badge; "Kaun khayega" list (avatar, name, note, Perfect / Tweak / Nahi); "Saaman" chips; "Kaise banega" numbered yellow steps; footer "Video recipe" (ghost, opens YouTube search) + "Menu mein daalo / Menu mein hai" | S7 | recipe/detail | GET /recipes/{id}?servings=; per-eater fit from engine |
| Plan | "Aaj ka {slot} menu", "{n} logon ke liye · har member ke liye kuch na kuch hai / kuch members ke liye aur dish chahiye"; dish rows with photo, note, remove; empty state "Menu khaali hai — Ghar se dishes ADD karo."; "Saaman ki list" with checkboxes (deduplicated ingredients); CTAs "Maharaj / cook ko bhejo" and "Missing saaman order karo"; toast confirmations | S8 | menu/day_menu | POST /menus, POST /menus/{id}/confirm → ticket; required-items check against stock |

### 1.2 Design tokens to encode in the Flutter theme

| Token | Value | Used for |
|---|---|---|
| haldi | #FFCC33 | Splash, headers, step numbers, chef button, "MAHARAJ KA PICK" badge |
| green | #0E7C3A | Primary CTA, links, veg mark, selected chip border, ADD button |
| green.dark | #0A5E2C / #095A29 | Hover text, CTA bottom shadow (3D press) |
| green.hero | #0E5F31 | Hero card background |
| ink | #1B1B18 | Body text, user chat bubble, toast, badges |
| ink.2 / ink.3 | #3A3A34 / #55544E | Secondary text, hints |
| ink.4 | #6B6A63 | Inactive nav, remove icons |
| paper | #F4F5EF | App background, input background |
| card | #FFFFFF with border #E6E6DF | Tiles, cards, bottom bars |
| cream | #F7F3E6 | Image placeholder background |
| fit / tweak / no badges | #E7F4EA on #0A5E2C, #FFF1C7 on #7A5200, #FCE6E2 on #8B2A17 | Fit badges everywhere |
| diet marks | veg #0E7C3A dot, egg #B86A00 dot, non-veg #8B2A17 triangle | Square mark on every card |
| display font | Bricolage Grotesque 800, letter-spacing -0.02em | H1s, household name, section titles |
| body font | Figtree 500–800 | Everything else. A Devanagari face must be added (F-11-01) |
| type scale | H1 40 / 30 / 28, section 19, card title 14, body 14, caption 12–12.5, badge 11 | |
| radii | 24 header bottom, 20 hero, 16 tiles/cards, 14 CTAs/inputs/chips-large, 12 icon buttons, 10 small buttons, 8 ADD, 6 badges, 999 chips | |
| heights | CTA 52, input 48, chip 36, segment 40, ADD 32, nav 68, icon button 44 | |
| motion | rise .45s (screen enter), popIn .55s with 3D tilt (tiles, staggered 70 ms), flipIn .6s (chat cards), thali spin 18 s, orbit 11 s, steam 2.6 s, chef bob 2.4 s, roti-flip typing 1 s, ticker 10 s, toast 2.2 s; all disabled under reduce-motion | Flutter: implement with implicit animations + a `MotionScale` that reads OS reduce-motion |

### 1.3 Reusable components the prototype defines (build these first in Flutter)

Chip (default / on), Segment control, CTA (with 3D press), Ghost button, ADD toggle, Diet mark, Fit badge (fit / tweak / no), Avatar (initial on colour, inset shadow), Recipe tile (grid), Recipe mini-card (chat), Member tile, Step number, Bottom nav with raised chef button, Toast, Typing indicator, Thali hero (3D CSS in prototype; in Flutter use a pre-rendered animated asset or Rive), Ticker search bar.

### 1.4 Copy: the prototype's Hinglish strings are the v1 string table

Take every visible string from the prototype into the `hinglish` locale as the default, then add English and Hindi. Examples the backend and app must reuse exactly: "Sabke liye perfect", "Sabke liye · {n} tweak", "{can}/{n} ke liye", "{names} ke liye nahi", "Sab khush, koi badlaav nahi", "Pyaaz-lahsun hai", "Isme anda hai", "Non-veg hai", "Maida hai", "Unki katori mein kam mirch", "Upar se laal mirch / achaar", "Portion chhota, salad zyada", "Kam tel mein banao", "Saath mein dahi/paneer", "Bachche ke liye alag, halka", "Favourite cuisine bhi", "Bilkul sahi", "Dhyaan rakha: …", "Sabki pasand dhyaan mein hai", "rotiyaan sek raha hoon…", "Is combo mein exact match nahi mila. {slot} ke liye ye sabse kareeb hain:", "{slot} ke liye {n} options — {why}. {k} mein poora parivaar kha sakta hai."

Reason strings come from the engine as keys; the app renders them per locale. The engine never returns free text.

### 1.5 Logic in the prototype that becomes real code

- **fitFor(member, recipe)** is the seed of the matching engine (Phase 3). Its order of rules is the spec: hard No's (Jain and not jain-safe; Veg vs egg/non-veg; Egg vs non-veg; No maida vs maida tag), then Tweaks (spice mismatch, low sugar, low oil, high protein, kid-friendly), then Fit with "Favourite cuisine bhi" when cuisine matches. The FRD review extends it with allergens, dislikes, no-onion-garlic, vrat days and eaters (F-5.2-*, F-5.6-01).
- **summarize(recipe)** gives the three badge states and the score `can*10 + perfect*3 + like*2 − 15 if anyone is No`; ties broken by minutes. Replace with the single formula from F-6-05 but keep the badge labels.
- **constraintLine()** picks up to three header constraints (Jain, low sugar, kam mirch for kids). Keep the priority rule from F-5.3-03 and hide health needs by default (F-5.3-05).
- **reply(query)** is a regex intent parser: slot words, halka/light, protein, mehmaan/special, baarish, tiffin/kid, jaldi/15 min, paneer, cuisine names, member names. These become the first 30 rows of the 200-query golden set and the rule-based fallback parser when the LLM times out (Phase 4).
- **Quick asks and chips** ("15 min mein kuch", "Kuch halka", "Baarish special", "Daughter ka tiffin", "Mehmaan aa rahe hain", "High protein"; follow-ups per slot) become a config table the admin panel can edit.
- **Recipe record shape** in the prototype (id, name, sub, mins, meals b/l/d, diet, jain, spice 1–3, tags, cuisine, colour, ingredients, steps, image) is the minimum the admin panel must capture per recipe, on top of the FRD data model. The 22 sample recipes are the seed rows for dev and demo.

### 1.6 Where the prototype stops, and what the build must add

| Gap | Prototype behaviour | What v1 needs |
|---|---|---|
| Cook mode (K1–K7), stock, ration, settings, paywall, invite | Not present | Designed in the same language before Phase 5 (decision 13) |
| "Cook ko bhejo" | Toast "Menu + saaman list cook ko WhatsApp par bhej di" | Real ticket creation + push to cook; WhatsApp only via share sheet (F-2-01) |
| "Missing saaman order karo" | Toast | Ration request flow (Phase 6) or hidden if stock ships later |
| Slots | Nashta / Lunch / Dinner only | Same three as Must; Tiffin and Shaam ka nashta as optional (F-5.3-01) |
| Diet model | Jain is a per-recipe boolean; no allergies, dislikes, vrat | Derived flags from ingredients; allergen picklist (decision 6) |
| Eaters | Every member counts for every meal | "Kaun kha raha hai?" step on the Plan screen before confirm (F-5.6-01) |
| Servings and scaling | None | Servings on Plan; scaled quantities on Detail (F-5.5-01, F-5.5-05) |
| Video recipe | YouTube search link | Keep as an external link for v1, or a curated video_url per recipe |
| Voice | Toast only | Speech-to-text in the query language; Should for v1 |
| Household name | Hard-coded "Purohit Parivaar" | From Household.name |
| Recipe photos | 22 embedded blobs | Object storage + CDN, WebP variants, uploaded through the admin panel |
| Language | Hinglish only, `lang="hi-Latn"` | Hinglish default for hi-IN devices, English otherwise (F-10-05); Hindi script as an option |

---

## 2. Repository and infrastructure

**Monorepo layout**

```
banega/
  backend/        FastAPI app, SQLAlchemy 2.x models, Alembic, engine, workers
  admin/          Admin panel (Starlette-Admin on top of the same models package)
  app/            Flutter app
  infra/          docker-compose.yml, Dockerfiles, env templates, nginx
  content/        CSV/JSON seed data: ingredients, staples, recipes (22 from prototype first), golden query set
  design/         Prototype HTML, exported tokens JSON, screens for the gaps in §1.6
  docs/           FRD v2, this plan, API contract (OpenAPI export)
```

**Docker Compose services (DB and backend separate, as decided)**

| Service | Image / role | Notes |
|---|---|---|
| db | Postgres 16 + pgvector | Own volume; daily pg_dump sidecar; never exposed publicly |
| api | FastAPI + Uvicorn (backend/) | Stateless; scales horizontally; talks to db over the compose network only |
| worker | Same image as api, runs an ARQ worker | Timers: due_at + 3 h auto-close, 30-min swap timeout, no-show escalation, 20:00 next-day notify, push fan-out, TTS pre-render |
| redis | Queue + cache + rate limits | OTP send limits, idempotency keys, session cache |
| admin | Starlette-Admin app (admin/) | Separate container and port, staff-only auth, same DB |
| nginx | Reverse proxy + TLS | Routes /v1 to api, /admin to admin |

Two compose files: docker-compose.yml (dev, hot reload) and docker-compose.prod.yml (pinned images, secrets from env, no bind mounts). Migrations run as a one-shot `alembic upgrade head` job before api starts.

**Backend conventions (from Appendix A of the review)**
- Base path /v1; every request scoped to the caller's household; foreign IDs return 404.
- Errors: `{code, message_en, message_hi, details}`.
- Idempotency-Key header on all creating or transitioning POSTs (confirm menu, rate, transition ticket).
- If-Match: version on ticket and menu writes; 409 on conflict.
- Cursor pagination on lists.
- JWT access 15 min, refresh 90 days rotated; tokens in Keystore/Keychain on the app.
- Structured JSON logging, request IDs, Sentry.

---

## 3. Delivery phases

Each phase ends with a demo and a test gate. Phases 2 and 3 can run in parallel with a content team feeding the catalogue.

### Phase 1 — Foundations and design system (2 weeks)
- Compose stack up, CI runs lint + tests + migration check on every PR.
- Schema v1: User, Household, HouseholdMembership (replaces User.role, F-8-01), Member, Invite, Device, NotificationPref, Subscription.
- Auth: phone OTP (provider abstraction with SMS + voice fallback), rate limits per F-5.1-01, invite links bound to phone and single-use (F-5.1-02), DELETE /me and DELETE /household with 7-day undo (F-5.1-03).
- Permission layer: one `can(actor, action, resource)` function implementing the §2.1 table, with one contract test per cell.
- Flutter: project skeleton, Riverpod, Dio client generated from OpenAPI, l10n scaffolding (hinglish, en, hi) seeded with the prototype strings (§1.4).
- Flutter design system from §1.2 and §1.3: theme tokens, the 16 components, a Storybook-style gallery screen that reproduces each prototype component side by side with a screenshot of the prototype. Sign-off: the FRD author compares gallery to prototype.
- Screens: Splash, Family, Prefs, Loading (§1.1) pixel-matched to the prototype, wired to the members API.

### Phase 2 — Catalogue and admin panel (3 weeks, overlaps Phase 3)
- Schema: Ingredient (name_en, name_hi, aliases, category, allergens[], flags {root_veg, onion_garlic, meat_type, egg, dairy, gluten}, scaling_rule, trackable), Staple (trackable subset), Recipe (name, sub, base_servings, mins, meal_slots[], dish_category, dish_group_id, cuisine, spice 1–3, tags[], colour, image, steps_en, steps_hi, vrat_ok, video_url, version), RecipeIngredient (qty, unit, is_main, optional), SubstitutionRule.
- Derived tags: jain_safe, no_onion_garlic, veg, egg, non_veg and allergens computed from ingredients on save; hand-tagging blocked (F-5.2-01a, F-6-06).
- Seed the 22 prototype recipes first so the app looks like the prototype from day one; the content team grows the catalogue toward 1,000.
- Admin panel (Starlette-Admin, staff login via email + TOTP):
  - CRUD for ingredients, staples, recipes, substitution rules, with a Draft → Reviewed → Published workflow and a Jain policy check that fails a recipe whose derived flags contradict its editorial tags.
  - Card preview: the recipe form shows the tile exactly as the app renders it (photo, mark, minutes, name, cuisine) so editors see what the family sees.
  - Bulk CSV import/export; image upload to object storage with WebP variants.
  - Config tables: quick-ask chips, follow-up chips per slot, cuisines, needs list, slot defaults, example ticker asks.
  - Users and households: search, view membership, subscription state, resend invite, block, hard-delete with audit log.
  - Golden query set editor for the Maharaj parser (F-5.4-03).
  - Read-only dashboards: tickets per day, on-time rate, LLM cost, OTP failures.
- Detail screen (§1.1) with scaling by servings and non-linear rules (F-5.5-05).

### Phase 3 — Matching engine and Home (2 weeks)
- Pure-Python engine package, no I/O, ported from the prototype's fitFor/summarize (§1.5) and extended per the review: input = recipe + eaters (diets, allergens, dislikes, needs, vrat day); output = fit / tweak / no + reason key. Property tests plus the prototype's fixture household (Papa veg low-sugar, Mummy veg, Dadi Jain, Daughter egg kid, Wife non-veg teekha) with expected badges for all 22 seed recipes.
- Score = fit coverage over eaters + learning + repetition penalty (3-day rule) + stock, one formula (F-6-05), replacing the prototype's ad-hoc score.
- GET /recommendations?slot&date uses the engine only, no LLM; p90 under 300 ms; cached per household + eaters hash.
- Home screen (§1.1) pixel-matched: header, ticker search bar, slot control, hero card, quick asks, tile grid, sticky menu bar, bottom nav; loading fallback at 3 s.

### Phase 4 — Maharaj chat (2 weeks)
- Pipeline: Parse (Claude, JSON schema, temperature 0, 2.5 s timeout, then the rule-based parser ported from the prototype's reply()) → retrieve (pgvector + filters) → rank (engine) → Write (Claude, temperature 0.3, 3 s timeout, then the prototype's template reply). Cards stream to the client before the reply text.
- Chat screen (§1.1): bubbles, mini-cards, follow-up chips, "rotiyaan sek raha hoon…" typing state, mic (Should).
- Per-user private sessions, 30-min idle expiry, 30-day retention job (F-5.4-01).
- Golden set of 200 queries in three scripts, seeded with the prototype's intents; CI asserts at least 95% parse accuracy.
- Cost guard: per-household daily LLM budget, cached parses for identical queries.

### Phase 5 — Day menu, tickets and cook mode (3 weeks)
- Plan screen (§1.1) plus the additions from §1.6: date selector (today + 6), "Kaun kha raha hai?" eaters and guests, servings, due time, assignee; "Cook ko bhejo" creates a real ticket.
- Ticket with the review's state table enforced server-side via POST /tickets/{id}/transitions, returning 409 with allowed next states.
- Duty schedule, backup, Unassigned queue, Chef-for-the-day claim, off-duty rule, no-show escalation timers in the worker.
- Notification matrix table (event × role × channel) driving FCM/APNs; in-app inbox is the source of truth.
- Flutter cook mode K1–K7 from the new designs (decision 13), in the prototype's language: Hindi-first, cook-mode type scale (F-4-04), per-step audio (on-device TTS, server fallback), offline read cache of today's and tomorrow's tickets (drift), Should-level offline write queue.
- WhatsApp-only cook path via share sheet; no server-sent WhatsApp in v1.

### Phase 6 — Stock, ration and out-of-stock (2 weeks, Should tier if scope is cut)
- Stock levels In/Low/Out per staple, thresholds, required-items check on ticket creation ("Saaman ki list" on Plan becomes live), ration request → admin approval → Bought; "Missing saaman order karo" becomes real.
- Out-of-stock ladder: save dish → swap ingredient (SubstitutionRule, engine re-check, cook_can_approve_swaps) → change dish (approval per §2.1, 30-min timeout) with a change log on the ticket.

### Phase 7 — Ratings, learning, billing, launch hardening (2 weeks)
- Ratings per eater with proxy rating, appreciation-first copy, ratings-off setting, learning signal only from Completed tickets.
- Subscriptions: server-side 7-day trial, Play RTDN + App Store Server Notifications webhooks, grace period, restore purchases; paywall screen from the new designs.
- Consent screen and DPDP notice, data export, deletion purge job, backups tested (RPO 24 h / RTO 4 h).
- Load test at 20 members × 1,000 recipes; reference ₹10–12k Android device passes Home under 1.5 s warm; thali animation replaced by a static thali on low-end or reduce-motion devices (F-10-04).
- Store submission checklist (account deletion, privacy labels).

---

## 4. Flutter app structure

```
app/lib/
  core/        api client, auth, storage, l10n, theme (tokens from §1.2), motion (reduce-motion aware)
  ui/          the 16 prototype components (§1.3) + gallery screen
  features/
    onboarding/  members/  home/  chat/  recipe/  menu/  cook_mode/  stock/  ratings/  settings/
  labels/      maps engine fit/tweak/no + reason keys to Perfect/Tweak/Nahi + locale strings
```
- State: Riverpod. Networking: Dio + generated OpenAPI client. Offline: drift for cached tickets and recipes, plus a queued-mutation table for cook writes.
- Two modes in one binary: family mode and cook mode; a family cook switches, a hired cook is locked to cook mode by role.
- Fonts: Figtree + Bricolage Grotesque (bundled, as in the prototype) plus a Devanagari face (F-11-01).
- Golden tests: each prototype screen at 390 × 844 compared against a prototype screenshot, plus every screen at 200% OS font scale.

---

## 5. Test gates per phase

| Gate | What must pass |
|---|---|
| Design system | Gallery screen signed off against the prototype by the FRD author; golden tests for Splash, Family, Prefs, Home, Chat, Detail, Plan |
| Permissions | One contract test per cell of the §2.1 table |
| State machine | Every row of the ticket table, plus each illegal transition returns 409 |
| Engine | Prototype fixture household yields the same badges as the prototype for all 22 seed recipes; Jain policy check; allergen test recipe returns No on every surface |
| Chat | At least 95% on the 200-query golden set; timeouts produce fallbacks, never errors |
| Scaling | Base-4 dal to 8 servings gives 1.5× salt and the same whistle count |
| Billing | Sandbox tests for trial → active → grace → expired → active on both stores |
| Offline | Airplane-mode cook can open a ticket and play every step |

---

## 6. Sequence and rough timeline

Phase 0 (1 wk) → Phase 1 (2) → Phases 2 + 3 in parallel (3) → Phase 4 (2) → Phase 5 (3) → Phase 6 (2) → Phase 7 (2). About 15 weeks to a store-ready build with one backend engineer, one Flutter engineer, one content/QA person, a designer for the §1.6 screens during Phases 1–4, and the FRD author on decisions. Moving Phase 6 to post-launch saves about 2 weeks and brings the Must count near an MVP.
