# Council synthesis — Banega FRD review

## 1. Synthesized verdict

**Verdict: approved with corrections applied.** The Builder's report was accurate (all quotes verbatim, FR counts right, the load-bearing gaps correctly identified) but mis-calibrated. Both reviewers were right about different things, and one reviewer claim was itself wrong. Every justified fix has been applied in the final report below.

**Consensus issues (both reviewers agreed):**
- Every FR-ID in the report is a reconstructed label (the ID column did not survive extraction); the Reading notes now say so plainly.
- The seven seeded Blockers were correct; eaters/servings, due time, Ingredient-vs-Staple, allergies, `jain_safe` and Hindi steps/TTS all stand.
- The Major bucket needed a calibration pass and the report needed tightening for the author.

**Corrections taken from the Opus review (all verified against the FRD):**
- **Rubric was not applied to its own findings.** Rewritten so Blocker = a core flow/schema cannot be built, or store rejection. Promoted to Blocker: F-2-02 permission/approval table, F-5.7-02 state machine, F-5.7-06 off-duty (three contradicting Musts), F-5.1-03 account deletion (Apple 5.1.1(v)). Demoted: F-2-01 WhatsApp to Major; F-2-03 to Minor and reframed (Opus was right: "without a second phone" means no separate login); F-9-02 and F-10-02 to Minor in a new Appendix A "Inputs for the technical design".
- **The two paste-ready tables contradicted each other.** F-5.9-02 is now folded into one canonical §2.1 table (adult members can approve, first response wins; family cook self-approves with admin notified).
- **Replacement state table had two bugs.** Auto-close now fires from Accepted too, and lands in "Not confirmed" (no rating prompt, no stock decrement, no learning) until the admin answers "Khaana bana?"; the family-cook path is exempt from "edit returns to New".
- **Scope self-contradiction.** New §7 "Scope impact" tags every proposed FR Must/Should/Could and gives the net count (72 Must after 12 additions and 6 demotions), with an honest option to cut a feature area. K13/K18/S8/C7 removed from the demotion list (already Should). M8 vrat, optional slots and the offline write queue are now Should.
- **Four missed findings added:** cook no-show escalation (F-5.7-12, Major), non-linear scaling of salt/spices/whistles (F-5.5-05, Major), regional languages and an English default on the family side (F-10-05, Major), health labels in the Home header (F-5.3-05, Minor).
- Split F-5.2-01 into `jain_safe` (Blocker) and diet taxonomy (Major); split the R4 step-count issue out of the Nit; softened F-5.4-02 and F-3-03; replaced F-6-01's unsound "40%" AC with a content check; fixed "15 items" vs 17; merged F-8-03 into F-8-02 and F-5.7-07 into F-5.7-02.

**One reviewer claim rejected:** Sonnet's "the file has 859 lines, not 1,255" is wrong; `wc -l frd.txt` and a direct read both give 1,255. Neither figure appears in the final report.

**Verification of the final report:** 254/254 quote fragments found verbatim in `frd.txt`; 111 findings with body and index severities reconciled by script (10 Blocker / 46 Major / 50 Minor / 5 Nit). Word count ~19,200: Blockers and Majors kept at full length, Minors and Nits compressed.

## 2. Final FRD review report

Saved at `C:\Users\PC\AppData\Local\Temp\claude\C--Users-PC-Desktop-banega\c32dbb2b-e33a-453d-b155-2e1d37e853fc\scratchpad\frd-review-final.md`. Full text follows.

---

# Banega FRD — Final Review Report

Document reviewed: "Banega — Functional Requirements Document", Sep 26, 2026, author @Anshul, 25 pages, 74 functional requirements (66 Must, 8 Should). Reviewed by the Council (one Builder review, two independent reviewers, one synthesis). Review date: 2026-09-26.

## 1. Executive summary

**Verdict: strong product thinking, not yet buildable.** The FRD is well above average. "Cooking is a role, not a person", a deterministic matching engine that the AI never overrides, a real out-of-stock ladder, measurable latency targets and a concrete design system are all things most FRDs lack. But three things every ticket depends on are never defined (who is eating, when the food is due, who may approve what), several Must requirements contradict each other, and the data behind stock and diets is too thin for the promises the product makes.

This report records **111 findings: 10 Blockers, 46 Majors, 50 Minors and 5 Nits.** They fall into five themes:

1. **Missing core concepts.** Eaters, servings and guests (F-5.6-01); due time (F-5.7-01); one canonical permission and approval table (F-2-02); a notification matrix (F-X-01).
2. **Contradictions between Must requirements.** Three different outcomes for a ticket when the cook goes off duty (F-5.7-06); a state table that cannot express the Family-cooks path or "Unassigned" (F-5.7-02); "multiple cooks" is Later while v1 has backup cooks and reassignment (F-2-05); Hindi audio is a Must while Hindi steps are an open question (F-5.7-03); "licensed" vs "publicly available" recipes (F-7-06).
3. **Engine correctness for Indian diets.** An undefined `jain_safe` (F-5.2-01a); no no-onion-garlic, pescatarian, halal or vrat rules (F-5.2-01b, F-5.2-02); free-text allergies claimed as hard exclusions (F-5.2-03); "not tagged" Tweak rules that make "Sabke liye" almost unreachable (F-6-01); a K4 example the engine can never produce (F-6-02).
4. **The data behind stock and substitutions.** A 110-item staple list cannot back 1,000 recipes (F-5.8-01); stock has no quantity model (F-5.8-02); three unreconciled stock representations (F-5.6-04); no source for ingredient swaps (F-5.9-01); recipe scaling that is not linear (F-5.5-05).
5. **Operational, legal and language gaps.** No account deletion, which Apple requires (F-5.1-03); no DPDP handling (F-X-02); personal data sent to the LLM vendor with no terms (F-7-02); no cook no-show escalation (F-5.7-12); no offline cook mode (F-10-01); no Devanagari typeface (F-11-01); Hindi-only cook mode and Hinglish-default family UI for a pan-Indian catalogue (F-5.7-04, F-10-05).

Fixing the 18 items in §8 makes the FRD buildable. Most fixes are additions of a few lines to one section, and each is written below as requirement text the author can paste in. §7 gives the net effect on the Must count, because the FRD already has more Musts than an MVP should and this report adds some.

## 2. Reading notes

- **Source.** The review works from the plain-text extraction of the PDF (`frd.txt`, 25 pages delimited by "Page N of 25" footers). Page numbers follow those footers. Layout-level issues (visual table structure, images) were not reviewed.
- **FR-IDs in this report are reconstructed.** The ID column did not survive text extraction: nearly every requirement row reads literally "FR- Must …" with the letter and number lost (only FR-F5 and FR-F6 survive intact). Every FR-xx label in this report (FR-A5, FR-K2, FR-M6 …) is therefore inferred from section order and content, as a citation aid. The requirement and acceptance-criteria text quoted is verbatim; the ID labels are not.
- **Extraction artefacts are not reported as defects.** The glyph "�" stands for ₹, en-dashes, arrows and multiplication signs ("50 per week" is read as "₹50 per week"). Quotes use "…" where a glyph or column break was dropped. Several two-column tables interleave in the extraction; they were read as follows:
  - Roles (p.1–2): Admin: phone OTP. Adult member: optional login via invite; edits own preferences, asks Maharaj, adds dishes. Profile-only member: no login. Cook: hired (own OTP, cook mode only) or family (same login, switches modes); gets tickets, opens recipes, marks Out, requests ration, closes tickets, sees ratings.
  - Ticket states (p.9): New (System) → Accepted, Cancelled. Accepted (Cook) → Stock issue, Cooking, Cancelled. Stock issue (Cook) → Accepted after a substitute is approved. Cooking → Ready → Completed. Completed (Cook or admin) → Rated. Cancelled (Admin), terminal.
  - FR-O2..O4 ACs (p.13): O2 enforced by the engine, not the LLM; O3 change log visible on the ticket; O4 cook can remove it.
  - Data model (p.17–19) and API tables (p.19–20): rows re-paired in document order.
- **Prototype.** Spot-checked by text search only. It has three slots (Nashta, Lunch, Dinner), uses only Figtree and Bricolage Grotesque, labels fit as "Perfect / Tweak / Nahi" and "Sabke liye perfect", and has no cook-mode, stock, ration or settings screens.
- **Quote verification.** Every quote fragment was machine-checked against `frd.txt` (whitespace-normalised) and found verbatim. This proves each fragment exists, not that it sits on the cited page; page references were spot-checked by hand against the footers.
- **Assumptions.** India-only launch in IST. "Admin" means the single household admin of §2. Legal points are flagged for sign-off, not given as legal advice.

## 3. Severity rubric

- **Blocker:** a core flow or the schema cannot be built as written (a load-bearing concept is undefined, or Must requirements contradict each other on a core flow), or the app would be rejected at store review.
- **Major:** a requirement is ambiguous or untestable enough to cause rework; a real household scenario has no defined behaviour; or a legal or privacy gap needs sign-off before launch.
- **Minor:** a local ambiguity, a missing acceptance criterion, an inconsistency with limited blast radius, or technical-design detail that belongs in the tech spec rather than the FRD.
- **Nit:** wording, typos, numbering.

Each finding appears once, where its fix belongs; other sections refer to it by ID. Fixes are written in the FRD's own style. Values such as default times are starting points for the author to confirm. Each new FR proposed is tagged Must, Should or Could; §7 totals them.

## 4. The ten Blockers (read these first)

The ten findings below stop engineering from starting, or would build the wrong product. They are given in full here and referenced by ID in the section-by-section list.

#### F-5.6-01 — Nobody defines who is eating a meal, how many servings, or guests
- Severity: **Blocker** (consensus: Builder and both reviewers)
- Where: FR-K2 AC (p.9); FR-P2 (p.8); FR-F1 (p.13); FR-R3 (p.8); §7.2 mehmaan intent (p.16)
- Quote: "servings, eaters, due time, notes" (p.9) | "Coverage line: whether every" (p.8)
- Problem: The ticket must hold `eaters` and `servings`, but no screen, FR or rule sets them. Everything downstream depends on them: coverage (P2 checks every member, including Papa who is travelling), ranking (a Jain Dadi who is not eating lunch still drags every score), quantities (R3, S3, S5), rating prompts (F1 "each eater") and guests (the "mehmaan" intent only sets a tag). This is the product's central unit of work, and it is missing.
- Fix: Add **FR-P7 Must**: "Each menu has 'Aaj kaun kha raha hai?': member chips (default = all active members; remembered per slot and weekday) plus a guest counter (adults, kids) with optional guest diet (veg / Jain / non-veg). Eaters drive ranking, coverage, servings (F-5.5-01), tweaks and rating prompts. Guests default to the strictest diet present among eaters unless set." Update FR-P2 to "every **eater**". Update §6.2 to sum over eaters, not all members. AC: "Removing Dadi from lunch eaters changes Jain-driven No badges on Home within 1 s, and the ticket shows the eater list and servings."

#### F-5.7-01 — "Due time" drives four features but is never defined
- Severity: **Blocker** (consensus)
- Where: FR-K2 AC (p.9); K1 screen (p.4); §5.9 step 6 (p.12); §12 `minutes_before_due` and "tickets completed on time" (p.24); §8 Ticket.due_at (p.18)
- Quote: "meal, with status and due" (p.4) | "If nobody answers within 30 min of the due time" (p.12)
- Problem: No FR says who sets the due time, the default per slot, or whether it can change. It orders K1, triggers the out-of-stock timeout, feeds an analytics property and a headline metric, and decides when off-duty reassignment and the no-show escalation (F-5.7-12) fire. Without it the ticket cannot be built.
- Fix: Add **FR-K2a Must**: "Every ticket has `due_at` = the time food should be ready. Defaults per slot are household settings (Nashta 08:30, Lunch 13:30, Dinner 20:30; optional slots per F-5.3-01), and the confirm sheet (F-5.6-02) lets the confirmer change it. Changing `due_at` after Accepted is an edit (FR-K7). AC: K1 sorts by `due_at`; the ticket shows 'Kab tak: 1:30'; 'on time' = Completed at or before `due_at` + 15 min."

#### F-2-02 — No permission matrix; "the family" is used as an actor; approval rules contradict each other
- Severity: **Blocker** (promoted from Major; absorbs Builder's F-5.9-02 and the reviewers' note that the two proposed tables contradicted each other)
- Where: §2 (p.1–2); FR-K2 (p.9); §5.9 intro and step 5 (p.12); §4 cook screens (p.4); §8 Household.cook_can_approve_swaps (p.18)
- Quote: "A ticket is created when the family … confirms a meal's menu" (p.9) | "The family always approves a dish change." (p.12) | "step 4 always goes to the admin" (p.12) | "without the accept and approval steps" (p.4)
- Problem: The roles table lists broad capabilities only. It never says whether an adult member can confirm a menu, choose the assignee, edit or cancel a ticket, approve a swap or dish change, approve ration, mark Bought, or rate for a child. "Family" is not a role, so server-side role checks cannot be written. §5.9 says "the family", then "the admin", approves dish changes; §4 says a family cook has no approval steps at all; the default of `cook_can_approve_swaps` is unstated; and the common weekday case (admin at work, another adult at home) has no answer.
- Fix: Add §2.1 "Permissions" as the **single canonical table** below, replace every "the family" actor with a role, and make §5.9 step 5 refer to it instead of restating it. Cells are proposed defaults.

| Action | Admin | Adult member (app) | Hired cook | Family cook (member with cook role) |
|---|---|---|---|---|
| Edit household, cook setup, settings, subscription | Yes | No | No | No |
| Add/remove members; edit any profile | Yes | Own profile only | No | Own profile only |
| Ask Maharaj; add/remove dishes on a day menu | Yes | Yes | No (cook mode) | Yes |
| Confirm menu (create ticket), choose assignee | Yes | Yes, if "Members can send to cook" is on (default on) | No | Yes, for tickets assigned to herself |
| Edit/cancel a ticket (F-5.7-02) | Yes | Only tickets they confirmed, before Accepted | No | Own tickets |
| Accept/start/complete a ticket; mark item Out | May mark Completed | No | Yes (own tickets) | Yes (own tickets) |
| Approve alt recipe / swap (§5.9 steps 2–3) | Yes | Yes (first response wins) | Only if `cook_can_approve_swaps` (default **on**) | Self, no approval |
| Approve dish change (§5.9 step 4) | Yes | Yes (first response wins) | No | Self, no approval; admin notified |
| Raise ration request; update stock | Yes | No | Yes | Yes |
| Approve ration request; mark Bought | Yes | No | No | Self (auto-approved); bill goes to the admin |
| Rate a meal; rate on behalf of a profile-only member | Yes; Yes | Yes; Yes | No | Yes; Yes |
| See named ratings | Yes | Own only | Per F-5.10-01 | Per F-5.10-01 |
| Claim Chef for the day | Yes | Yes | n/a | Yes |

Rule for the admin-as-cook case (F-2-04): when approver and requester are the same user, the step is skipped and logged as self-approved. AC: "Every endpoint in §9.1 enforces this table server-side; one contract test exists per cell; an approval request goes by push to all eligible approvers at once."

#### F-5.7-02 — The ticket state machine has unreachable, missing and contradictory transitions
- Severity: **Blocker** (promoted from Major; absorbs F-5.7-07 on the FR-K7 edit window; replacement table corrected per the Opus review)
- Where: Ticket states table (p.9); FR-K7, FR-K11, FR-K14, FR-K16 (p.9–11); §2 Family cooks (p.2); §5.9 trigger (p.12)
- Quote: "Completed Cook or admin after serving" (p.9) | "Rated (after ratings come in)" (p.9) | "Admin can edit or cancel a ticket" … "until status is Cooking" … "Later edits need cook acceptance" (p.9) | ""Unassigned" and the admin is" (p.10)
- Problem: "Unassigned" is used by K11 and K14 but is not a state. "Stock issue" can only follow Accepted, although the K6 example ("dahi khatam hai") happens during Cooking and §5.9 also raises it at creation as a system action while the table says "set by Cook". Nothing leaves Stock issue except Accepted, so such a ticket cannot be cancelled. "Rated" has no row. The Family-cooks setup has "no accept step", but New → Cooking is not a legal transition. Nothing happens if the cook never taps Completed, which is common, and F1 ratings, S4 stock and F6 history all wait on it. FR-K7's "until Cooking" and "later edits need acceptance" can be read two ways. Only the admin is named as editor, although members confirm menus.
- Fix: Replace the table with the following. Stock issue becomes a flag, Rated a timestamp, and an unconfirmed auto-close never fires ratings, stock or learning.

| From | To | Actor | Condition / setups |
|---|---|---|---|
| (none) | New | System | Menu confirmed with a hired-cook assignee |
| (none) | Accepted | System | Menu confirmed and the assignee is a family cook or the confirmer (no accept step) |
| (none), New | Unassigned | System | No assignee, or assignee Off duty (F-5.7-06) |
| Unassigned | New / Accepted | Admin reassign, or a member claiming Chef for the day (K16) | First claim wins; New for a hired cook, Accepted for a family cook |
| New | Accepted | Assignee (hired cook) | |
| New, Accepted | New ("Updated") | Admin or confirmer edit (FR-K7) | Hired-cook tickets only; the cook re-accepts. Family-cook tickets stay Accepted and show "Updated" |
| Accepted | Cooking | Assignee | Before Cooking: edits allowed. During Cooking: only "Add note" and Cancel |
| Cooking | Ready | Assignee | Optional; may be skipped |
| Cooking, Ready | Completed | Assignee or admin | Fires F1 prompts, S4 stock, F6 history |
| Accepted, Cooking, Ready | Not confirmed | System | `due_at` + 3 h with no Completed. No rating prompt, no stock decrement, no learning signal. Admin is asked "Khaana bana?" (Yes → Completed, `completed_by = admin`; No → Cancelled) |
| New, Unassigned, Accepted | Cancelled | Admin, confirmer, or family cook on her own ticket | Cook notified |
| Cooking | Cancelled | Admin | Reason required; cook notified |
| any open state | (flag) `stock_issue_open = true` | Assignee or System (creation-time check) | Cleared per §5.9; does not change status |
| Completed | (timestamp) `rated_at` | System | When the first rating arrives |
| WhatsApp-only tickets | Accepted / Completed | Admin | Per F-5.6-03 |

AC: "The server rejects any transition not in this table with 409 and the allowed next states. A ticket in Not confirmed for 24 h is closed as Cancelled without any learning or stock effect."

#### F-5.7-06 — Off duty: tickets stay, move to backup, or go to Unassigned? Three Musts, three answers
- Severity: **Blocker** (promoted from Major: three Must requirements contradict each other on the core assignment flow)
- Where: FR-K10, FR-K11, FR-K14 (p.10); §5.7 "Turning back On duty" (p.10)
- Quote: "Tickets already accepted stay with" … "them unless reassigned" (K10) | "Open and upcoming tickets for the" … "off-duty period move to" … ""Unassigned" and the admin is" … "alerted" (K11) | "When the primary goes Off duty," … "tickets go to the backup first, then" … "to Unassigned" (K14)
- Problem: For an Accepted dinner ticket when the cook goes off duty at 16:00, K10 keeps it with the cook, K11 moves it to Unassigned, and K14 sends it to the backup. All three are Must. It is also unclear whether tickets moved to the backup come back when the primary returns early.
- Fix: Replace K10, K11 and K14 with one rule: "When a cook goes Off duty for a period P: (1) tickets in Cooking stay with them; (2) New or Accepted tickets with `due_at` in P go to the backup if the backup is On duty for that `due_at`, otherwise to Unassigned, and the admin is alerted; (3) tickets moved to the backup stay with the backup even if the primary returns early; (4) new tickets during P follow (2). AC: a scripted test of each case gives exactly one assignee."

#### F-5.2-01a — `jain_safe` is undefined, so the engine's central promise fails for Jain members
- Severity: **Blocker** (split from Builder's F-5.2-01; the diet-taxonomy part is F-5.2-01b, Major)
- Where: FR-M2 (p.6); §6.1 Jain rule (p.14); §6.3 (p.15)
- Quote: "Diet: exactly one of Veg, Jain, Egg, … Non-veg" (p.6) | "Pyaaz-lahsun hai" (p.14) | "jain_safe (bool)" (p.15)
- Problem: "The AI never overrides a No" is only as good as the diet model. Jain practice excludes root vegetables (potato, onion, garlic, carrot, radish, beetroot, ginger) as well as onion and garlic. The only reason text is "Pyaaz-lahsun hai", and `jain_safe` has no definition, so taggers may mark aloo dishes as Jain-safe. That puts a direct No violation in front of a core persona ("Dadi (Jain)"), and the definition decides both the content pipeline and the ingredient flags in the schema.
- Fix: Define in §6.3: "`jain_safe` = veg AND no onion, garlic, potato, carrot, radish, beetroot, fresh ginger, sweet potato or other underground vegetables AND no honey, mushrooms or yeast-fermented items, per the Banega Jain content policy (appendix, signed off by a Jain reviewer)." Derive it from ingredient flags (F-6-06), never hand-tag it. AC: "An automated check fails any recipe tagged `jain_safe` that contains an ingredient flagged `root_veg` or `onion_garlic`." Show the specific reason: "Pyaaz-lahsun hai" or "Aloo (zameen-kand) hai".

#### F-5.2-03 — Allergies are a Should, free text, yet claimed as "hard exclusions"
- Severity: **Blocker** (consensus)
- Where: FR-M6 (p.6); §6.1 Allergy rule (p.14)
- Quote: "FR- Should Free-text dislikes and allergies" … "Allergy items become hard" … "exclusions in the matching engine" (p.6) | "Recipe contains a listed allergen" (p.14)
- Problem: A free-text string ("peanut allergy", "moongphali", "mungfali se allergy") cannot reliably become a hard exclusion: the engine needs ingredient IDs, and `Recipe.ingredients` only references staples. Allergy is a Should, so it can slip out of v1 while the product still promises safety. A child with a peanut allergy then sees a dish with peanuts in the tadka marked "Sabke liye".
- Fix: Make it **FR-M6 Must** (promoted from Should) and split it: (1) "Allergies: multi-select from a fixed allergen list (peanut/moongphali, tree nuts/kaju-badaam, milk/doodh, gluten/gehun, sesame/til, soy, egg, fish, shellfish/jhinga, mustard/sarson) plus 'other' free text." (2) "Picked allergens are hard exclusions over `Ingredient.allergens[]` (F-5.8-01). 'Other' free text never auto-excludes; it shows a warning on Recipe detail and on the ticket." (3) "Recipe detail shows 'Allergy info is a guide; check packaged ingredients' for any member with allergies." AC: "For every allergen, a test recipe containing it returns No for an allergic member on Home, chat, Recipe detail, out-of-stock suggestions (FR-O2) and chat fallbacks (FR-C6)."

#### F-5.8-01 — A 110-item staple catalogue cannot back every ingredient of 1,000 recipes
- Severity: **Blocker** (consensus)
- Where: §5.8 intro (p.11); FR-S3 (p.11); §7.4 (p.16); §8 Recipe.ingredients, Staple (p.18)
- Quote: "The full starter catalogue of about 110 items is" (p.11) | "ingredients[{staple_id, qty, unit}]," (p.18) | "every ingredient of every" (p.11) | "ingredients mapped to staples" (p.16)
- Problem: Every recipe ingredient must reference a Staple, yet the catalogue has about 110 items and lives outside the FRD. Pan-Indian recipes need several hundred distinct ingredients: regional vegetables (tinda, parwal, kundru, drumstick, raw banana), seafood cuts, mutton vs chicken, fresh herbs, regional spices (kokum, panch phoron, kalpasi). The implementer faces three bad options: invent staples, leave ingredients unmapped (S3 and §5.9 break), or drop recipes. This decides the schema and the content pipeline.
- Fix: Split the concepts in §8: "**Ingredient** (global, ~600–800 items: name_en, name_hi, aliases[], category, allergens[], flags {root_veg, onion_garlic, meat_type, egg, dairy, gluten}, purchase_unit, pack_size, perishable, scaling_rule per F-5.5-05) and **Staple** (the subset tracked in the pantry; `Ingredient.trackable = true`)." Recipe.ingredients references `ingredient_id`. FR-S3 AC: "Tracked ingredients show In/Low/Out; untracked ones show 'Check karein' and are never auto-marked missing." Bring the 110-item list into a versioned appendix of the FRD.

#### F-5.7-03 — Hindi audio read-out is a Must while "Hindi-script steps" is still an open question, and no TTS service is listed
- Severity: **Blocker** (consensus)
- Where: FR-K5 (p.9); §13 Still open (p.25); §9.2 (p.21); §7.4 (p.16)
- Quote: "Includes audio read-out in Hindi" (p.9) | "Do we need Hindi-script recipe steps for cooks who don't read English?" (p.25)
- Problem: A Hindi read-out needs Hindi step text, authored or machine-translated and reviewed. That is exactly what §13 leaves open. §7.4 content targets and §9.2 services mention neither Hindi steps nor TTS. The Must cannot be met as scoped, and the content cost (1,000 recipes × Hindi steps) is not in the plan.
- Fix: Close the question. Add to §7.4: "Every recipe ships with steps in English and in Hindi (Devanagari), with Hinglish as display fallback. Hindi steps are machine-translated and reviewed by a native speaker." Add to §9.2: "TTS: on-device Android/iOS Hindi voices where available, with server TTS (hi-IN) as fallback; audio cached per recipe." FR-K5 AC: "Play/pause per step; read-out works offline for today's tickets (F-10-01); speed 0.8×–1.2×." If the content cost is not acceptable, demote FR-K5 to Should and say so.

#### F-5.1-03 — No account or household deletion requirement (store rejection risk)
- Severity: **Blocker** (promoted from Major: Apple App Store Review Guideline 5.1.1(v) requires in-app account deletion for apps that create accounts, so the iOS build would be rejected; DPDP erasure right also applies)
- Where: §5.1 (p.5); §10 Privacy (p.22)
- Quote: (absent — nearest text: "encrypted at rest, never sold, deletable with the household")
- Problem: The Privacy NFR promises deletion, but no FR, screen or endpoint implements it. The FRD also does not cover a member leaving a household or a hired cook leaving (F-5.7-10).
- Fix: Add **FR-A8 Must**: "Admin can delete the household from settings: 7-day undo window, then hard delete of all household data (members, menus, tickets, ratings, chats, pantry). Store subscriptions must be cancelled in the store (link provided). Any logged-in member can delete their own account, which unlinks their User; the admin chooses whether the profile stays. AC: after deletion, no API returns the household's data, and backups purge it within 30 days." Add screen S9 Settings (F-4-01) and `DELETE /household`, `DELETE /me` (F-9-01).

## 5. Findings by section

### 5.1 Overview and goals (§1)

#### F-1-01 — Four different "how many options" numbers
- Severity: Minor
- Where: §1 Goals (p.1); FR-C3 (p.7); §7.1 step 3 (p.15); FR-H3 (p.6)
- Quote: "Return 3…6 meal options per query" (p.1) | "Reply = one short message + 3…4" (p.7) | "take the top 4" (p.15) | "Recipe grid shows 8 top-ranked" (p.6)
- Problem: Each surface uses a different count (3–6, 3–4, 4, 8), so the §1 goal cannot be tested.
- Fix: "Home grid 8 (FR-H3), Maharaj ka pick 1, chat 3–4 cards (FR-C3; fewer only when FR-C6 applies)." §7.1 step 3: "take the top 4 (minimum 3 unless fewer exist)".

#### F-1-02 — The prototype is "source of truth" but has no cook, stock, ration or settings screens
- Severity: Major
- Where: §1 Reference prototype (p.1); §4 Cook app screens (p.4–5)
- Quote: "is the source of truth for layout, copy and motion"
- Problem: The prototype has three slots and family-side screens only; there are no hits for "Aaj ke tickets", "Rasoi", "On duty" or "Kitchen staples". K1–K7, the ration approval screen, the rate sheet, settings and the paywall have no layout source. The prototype also uses labels the engine does not ("Perfect / Tweak / Nahi" vs Fit/Tweak/No, F-5.5-02). Nothing says which document wins when they disagree.
- Fix: Add to §1: "Precedence: this FRD governs behaviour, data and rules. The prototype governs layout, copy and motion only for screens S1–S8. Screens K1–K7, the ration approval screen, the rate sheet, the ticket status card, settings and the paywall are specified in [design file, version x]. Where the FRD and prototype conflict on copy, the FRD wins and the prototype is updated. AC: every screen ID in §4 links to exactly one design source."

### 5.2 Users and roles (§2)

#### F-2-01 — Admin "receives WhatsApp messages from the app", but v1 has no WhatsApp Business API
- Severity: Major (demoted from Blocker: one role-cell clause and one §9 sentence, neither a Must FR; a one-line rewrite fixes it)
- Where: §2 Roles table, Household admin (p.1); §9 intro (p.19); §9.2 WhatsApp share intent (p.21)
- Quote: "recieves messages on whatsapp from the app / maharaj on low inventory etc" (p.1) | "the backend talks to the LLM, recipe sources and" (p.19) | "Device share sheet; no … WhatsApp Business API in v1" (p.21)
- Problem: Without the Business API, neither the backend nor Maharaj can message anyone on WhatsApp; a share intent only opens WhatsApp on the user's own phone. One listed admin capability cannot be built, and §9's intro contradicts §9.2.
- Fix: Role cell: "Receives push and in-app alerts (low stock, ration requests, stock issues, unassigned tickets). Can share menus, bills and tickets to WhatsApp through the device share sheet." §9 intro: "the backend talks to the LLM, the vector index, the SMS provider, FCM/APNs and the stores." Add under Later: "WhatsApp Business API for admin alerts (template messages, opt-in)." AC: "No v1 flow requires a server-originated WhatsApp message."

#### F-2-03 — Can a profile-only member (no login) hold the cook role?
- Severity: Minor (demoted from Major and reframed: the Opus review is right that FR-A5's "without a second phone" most likely means "no separate device or login for cook mode", which matches §2's "same login, switches modes"; the open question underneath is still real)
- Where: FR-A5 AC (p.5); §2 setup table, Family cooks (p.2); FR-K1 (p.9)
- Quote: "a family member can … be picked as cook without a … second phone" (p.5) | "No separate cook login; tickets appear … as "Aaj ka plan" in her own app" (p.2)
- Problem: When Mummy cooks but has no login (profile-only), she has no "own app", cannot accept swaps, raise ration, toggle duty or claim tickets. The FRD does not say whether such a member can be the cook or who taps her buttons.
- Fix: FR-A5 AC: "A family member holds the cook role either (a) with her own login (invited per FR-A3), tickets in her 'Aaj ka plan' tab; or (b) as a profile-only cook with no login, tickets in the admin's 'Aaj ka plan' tab, where the admin performs her ticket actions and sets On/Off duty." Add `Cook.login_mode (own / via_admin)`.

#### F-2-04 — Admin-as-cook (the most common case) collapses the approval flows
- Severity: Major
- Where: §2 (p.1–2); FR-S6 (p.12); §5.9 step 5 (p.12); FR-K7 AC (p.9)
- Quote: "One household account holds one admin, many member profiles and optional cook" (p.1) | "Admin approves, edits or rejects a" (p.12)
- Problem: In a large share of homes the admin (usually mom) also cooks. The FRD then routes her dish changes to herself (step 5), her ration requests to herself (S6), and her own edits for her own acceptance (K7). The result is either pointless self-approval screens or undefined short-circuits.
- Fix: Add **FR-K19 Must**: "When the approver and the requester are the same user, approval steps are skipped and logged as 'self-approved'. Applies to §5.9 steps 2–4, FR-S6 and FR-K7 edits. AC: an admin who is also the assignee never sees an approval prompt for her own action; `change_log` records `approved_by = self`." (Also stated in the F-2-02 table.)

#### F-2-05 — "Multiple cooks per household" is Later, yet v1 has Both, Rotates, primary + backup, Chef for the day and reassignment
- Severity: Major
- Where: §3 scope table, Menu row (p.3); §2 setups (p.2); FR-K11, FR-K14–K17 (p.10–11); §8 Household relations (p.18)
- Quote: "attendance and salary, multiple … cooks per household" (p.3) | "Hired cook for some meals, family" (p.2) | "Admin sets a primary cook and an … optional backup cook from the" (p.10)
- Problem: The Later column pushes multiple cooks out of v1, but four setups and seven Must FRs need several cook-role holders per household (and `Household has many Cooks`). Engineering cannot tell whether to build multi-assignee tickets.
- Fix: Replace the Later cell with "multiple **hired** cooks per household". Add to §2: "v1 supports at most one hired cook plus any number of family members with the cook role. Exactly one primary; at most one backup; Chef for the day is a per-ticket override." AC: "Adding a second hired cook shows 'Abhi ek hi hired cook' and is blocked."

#### F-2-06 — The same hired cook in two households has no defined v1 behaviour
- Severity: Major
- Where: §8 User relations (p.17); §13 Decisions (p.25)
- Quote: "belongs to one Household" (p.17) | "Phase 2. v1 onboards families; the cook is only the" (p.25)
- Problem: Urban hired cooks commonly work in 2–4 homes. In v1 a second household will enter the same phone number, and the backend must reject, silently move, or merge; the FRD picks none. Rejecting locks the second family out of the product.
- Fix: Add **FR-K20 Must**: "A phone number can hold a hired-cook membership in at most one household in v1. If a second admin adds it, the admin sees 'Ye number dusre ghar mein cook hai' and can add the cook as WhatsApp-only (F-5.6-03) or ask the cook to leave the first household. AC: no user is linked to two households, and no household data is visible across households." Model as `HouseholdMembership` (F-8-01) so phase 2 needs no migration.

#### F-2-07 — Changing the cook setup mid-week has no rule for open tickets
- Severity: Minor
- Where: §2 (p.2)
- Quote: "The setup can be changed any time in settings."
- Fix: Append: "A setup change applies to tickets created after it. Open tickets keep their assignee. Tickets assigned to a cook who no longer holds the role move to Unassigned and the admin is alerted."

#### F-2-08 — "Maharaj" names both the AI and the hired cook
- Severity: Minor
- Where: §2 setup table (p.2); §1 (p.1)
- Quote: "Hired cook Maharaj / didi with their own" (p.2) | "Suggestions come from an AI assistant called Maharaj." (p.1)
- Problem: "Maharaj" is the everyday word for a hired cook, so "Maharaj ka message" is ambiguous in a home with a human Maharaj; K6 (cook) and K4 (AI) messages would carry the same name.
- Fix: §11 copy rule: "The hired cook is always shown by name ('Ramesh ji'), never as 'Maharaj'. 'Maharaj' refers only to the AI." Setup table: "Hired cook (cook / didi)".

#### F-2-09 — Wording: typo, two names for one action, gendered defaults
- Severity: Nit
- Where: §2 (p.1–2); §5.10 (p.14)
- Quote: "recieves" (p.1) | "Maharaj, Order staples," (p.1) | "She can turn ratings off from her own settings." (p.14)
- Fix: "receives"; rename "Order staples" to "order missing items / approve ration"; add a copy rule that cook-referring strings are gender-neutral or use `Member.gender` (optional), since Hindi verbs are gendered and §5.7 names fathers and teenagers as cooks.

### 5.3 Scope and pricing (§3)

#### F-3-01 — "Everything else waits" contradicts the scope table, and 66 Musts is not an MVP
- Severity: Major
- Where: §3 (p.2); §5 intro (p.5)
- Quote: "detail and the day menu. Everything else waits." (p.2) | ""Must" items block v1 release" (p.5)
- Problem: The opening sentence scopes v1 to five areas; the table and §5.7–5.10 add a cook app, duty schedules, Chef for the day, stock, ration, out-of-stock AI, ratings and learning. 74 FRs, 66 Must, and every Must blocks release, so nothing can be traded off when the schedule slips. (This report itself adds Musts; see §7 for the net count and the demotions that offset them.)
- Fix: Rewrite: "v1 is a mobile app (iOS + Android) covering onboarding, recommendations, chat, recipe detail, the day menu, the cook app with daily tickets, kitchen stock and ration, out-of-stock handling, and ratings." Add a third priority, "Could" (may ship after launch). Demote to Should: K9 recurring schedules, K15–K17 Chef for the day, S4 auto-decrement, F4 weekly summary; demote the FR-F5 "propose a tweak" clause to Could. AC: "The Must list is signed off against a delivery estimate."

#### F-3-02 — Future-date menus are needed, but the weekly planner is Later and no UI picks a date
- Severity: Major
- Where: §3 table (p.3); FR-S5, FR-S8 (p.12); FR-K9, FR-K11 (p.10); §9.1 `/menus?date=` (p.20)
- Quote: "Weekly planner, leftovers," (p.3) | "items needed for tickets in the" (p.12) | "Weekly ration suggestion based on … the week's planned tickets" (p.12)
- Problem: S5 (tickets in the next 48 h), S8 (the week's tickets), K11 (upcoming tickets during leave) and the `date=` API all assume menus for future dates. Home and S8 only offer slot tabs for today.
- Fix: Add **FR-P6 Must**: "The day menu has a date selector covering today plus 6 days. A ticket for a future date is created on confirm and notified to the cook at 20:00 the evening before. AC: a menu confirmed for tomorrow appears in K1 tomorrow and counts in S5." Scope note: "The Weekly planner (Later) is the multi-day grid view; single-date future menus are v1." (If P6 is cut, S5 must say "today's tickets" and S8 must move to Later.)

#### F-3-03 — Subscription lifecycle is under-specified
- Severity: Major
- Where: §3 Pricing (p.3); FR-A6 (p.5); §9.2 billing (p.21)
- Quote: "then 50 per week for all v1 features, billed as an auto-renewing weekly subscription through Google Play and the App Store" (p.3)
- Problem: Undefined: whether the trial is a store intro offer or server-side ("from household creation" implies server-side); restore purchases; what happens when the admin changes phone or platform, or the admin role moves while the store subscription stays tied to the old person's store account; billing retry and grace; refunds; trial abuse by creating a new household from another number. (Store billing handles the recurring-payment mandate, so that is not a risk the FRD needs to address.)
- Fix: Add **FR-A7 Must**: "Trial is server-side, 7 days from household creation, one per phone number and device ID. Purchase is by the admin; restore purchases on login. Store server notifications (Play RTDN, App Store Server Notifications) update Subscription.status within 5 min. Billing retry: 3-day grace with full access and a banner. Admin transfer keeps the subscription until its renewal date, then the new admin subscribes. AC: each transition (trial → active → grace → expired → active) is covered by a sandbox test on both stores."

#### F-3-04 — Currency symbol missing in the extraction; price hard-coded in the data model
- Severity: Nit
- Where: §3 (p.3); §8 Subscription (p.18)
- Quote: "then 50 per week for all v1 features" (p.3) | "price_inr (50/week)" (p.18)
- Fix: Confirm "₹50" in the PDF (probably an extraction artefact). In §8, replace `price_inr (50/week)` with `product_id, price_inr (from store)`, since §3 says the price will change.

### 5.4 Screens and flow (§4)

#### F-4-01 — The screen inventory omits screens the FRD relies on
- Severity: Major
- Where: §4 (p.3–5); §2 (p.2); §5.9 step 5 (p.12); §5.10 (p.14)
- Quote: "if the admin allowed it in settings" (p.12) | "a ticket status card on Home, a ration approval screen" (p.5)
- Problem: Settings (cook setup, swap approval, ratings off, notifications, language, delete account), a paywall, invite and cook management, ration approval, the rate sheet, an Unassigned-tickets view, the Chef-for-the-day claim, the Rasoi view on the family side and the "who is eating" step (F-5.6-01) have no screen ID, purpose, actions or navigation.
- Fix: Add rows S9 Settings; S10 Paywall / subscription; S11 Cooks and invites; S12 Ticket status card + Unassigned list; S13 Ration approval; S14 Rate the meal; S15 Rasoi stock (family view). Give each a purpose, main actions, "Goes to" and the FR-IDs it satisfies. AC: "Every FR maps to at least one screen ID."

#### F-4-02 — The Loading screen's 3 s maximum has no timeout behaviour
- Severity: Minor
- Where: §4 S5 (p.3)
- Quote: "computed (max 3 s)"
- Fix: "S5 shows for at least 1.2 s and at most 3 s. At 3 s, Home opens with any ranked results available; if none, it shows a curated fallback list for the slot and retries in the background."

#### F-4-03 — Two cook screens have loose ends
- Severity: Minor
- Where: §4 K4, K6, K7 (p.4–5)
- Quote: "Accept suggestion; ask"
- Fix: K4: "Ask family (opens the FR-K6 thread pre-filled with the missing item)". K6: "Send to admin (Family-cooks setup: 'Save list', no approval)". K7 Goes to: "K1".

#### F-4-04 — "Large type" for cook mode is not testable
- Severity: Minor
- Where: §4 Cook app screens (p.4); §11.2 (p.23)
- Quote: "Hindi-first copy, large type and icons"
- Fix: "Cook mode type scale: body 20 px, labels 18 px, minimum 16 px. Primary actions 56 px tall with icon and label. Follows OS font scaling to 200% without truncating ticket content."

### 5.5 Account and household (§5.1)

#### F-5.1-01 — OTP acceptance criterion is untestable, and resend, rate-limit and session rules are missing
- Severity: Major
- Where: FR-A1 (p.5)
- Quote: "OTP arrives in under 30 s; 3 wrong attempts lock for 10 min"
- Problem: SMS delivery time depends on the operator and DLT routing, which the team cannot control. Resend, send-rate limits (SMS-pumping fraud is a real cost), logout, multi-device login and phone-number change are not covered.
- Fix: FR-A1 AC: "OTP request dispatched to the provider within 2 s (server log). Resend after 30 s. Max 5 sends per number per hour and 10 per device per day. 3 wrong attempts lock that number for 10 min. Logout on this device and 'log out all devices' in settings. Changing a phone number requires OTP on both numbers, or admin re-invite." Should: "Voice OTP if SMS fails twice." (Token lifetimes belong in Appendix A.)

#### F-5.1-02 — The invite link logs the invitee straight in
- Severity: Major
- Where: FR-A3 (p.5)
- Quote: "Invite an adult member by … WhatsApp link" | "Invitee lands logged in to the same household"
- Problem: WhatsApp links get forwarded, especially in family groups. A self-authenticating link gives anyone who receives it access to diet and health-like data and to menu control.
- Fix: FR-A3 AC: "The link opens the app with the household pre-selected. The invitee still verifies their own phone by OTP. The invite is bound to the phone number the admin entered, single-use, expires in 7 days; the admin can revoke pending invites. Opening a used or expired link shows 'Invite purana ho gaya — admin se naya maangiye'."

#### F-5.1-04 — Demo family lifecycle undefined
- Severity: Minor
- Where: FR-A4 (p.5)
- Quote: "Demo data is clearly labelled and … can be cleared"
- Fix: "The demo is a local, read-only sandbox: no household is created, no trial starts, 'Send to cook' shows 'Demo mein nahi'. 'Set up my family' starts S2 with empty data."

#### F-5.1-05 — "Read-only after expiry" does not say what happens to the cook and today's tickets
- Severity: Minor
- Where: FR-A6 (p.5)
- Quote: "expiry the app is read-only until" | "household including the cook"
- Fix: "On expiry, tickets already confirmed for today and tomorrow remain fully workable by the cook. No new menus, chats or tickets. History stays viewable. Reminders go to the admin by push and banner on day 5 and day 7 at 10:00 IST. The cook sees 'Plan band hai, admin se baat karein' on K1 only after the last open ticket closes."

#### F-5.1-06 — One user, one household
- Severity: Minor
- Where: FR-A2 (p.5); §8 User (p.17)
- Quote: "Create one household with a name"
- Fix: State it: "v1: a phone number belongs to exactly one household. Switching households is Later." Adult children who manage a parents' kitchen in another city are a known Later case; build on `HouseholdMembership` (F-8-01).

### 5.6 Member profiles (§5.2)

#### F-5.2-01b — Four diets cannot model real Indian households
- Severity: Major (split from the `jain_safe` Blocker, F-5.2-01a)
- Where: FR-M2 (p.6); §6.1 (p.14)
- Quote: "Diet: exactly one of Veg, Jain, Egg, … Non-veg" (p.6)
- Problem: There is no "no onion-garlic but not Jain" diet (Vaishnav, Swaminarayan, ISKCON, many Brahmin households and elders). "Non-veg" is treated as eating everything, but households exclude beef, exclude pork, require halal, or eat fish and egg only (Bengali, Konkani, coastal homes). There is no dairy-free option.
- Fix: Replace FR-M2: "Diet (single-select): Veg, Jain, No onion-garlic (veg), Eggetarian, Pescatarian (fish + egg), Non-veg. For Non-veg, optional exclusions (multi-select): No beef, No pork, Halal only. Optional flag: No dairy." Derive the flags from ingredients (F-6-06). If the team wants to hold v1 to fewer values, add at least No onion-garlic and No beef, and list the rest under Later explicitly.

#### F-5.2-02 — Fasting (vrat) and weekday rules are absent, even from Later
- Severity: Major
- Where: §5.2 (p.6); §3 Later (p.3)
- Quote: (absent — nearest text: "seasonal and festival menus")
- Problem: Weekly fasts (Monday, Tuesday, Thursday, Saturday), Ekadashi, Navratri, Karva Chauth, Sawan and Ramzan timing change what one member eats on a given day; weekday no-meat rules apply to the whole household. These drive daily "aaj kya banega" decisions. Without them the engine shows Fit for dishes that person will refuse today, and the family stops trusting the badges.
- Fix: Add **FR-M8 Should** (with an explicit Later plan if it slips): "Per member, optional recurring diet days: weekday rules ('Mangalvaar veg', 'Somvaar vrat') and one-off fast dates. On such a day the member's diet is overridden (vrat → `vrat_ok` recipes only; veg day → Veg rules)." Add **FR-M9 Could**: household-wide weekday rule. Add the recipe tag `vrat_ok` now, so content is ready. AC: "On a member's vrat day, a non-vrat recipe shows No with reason 'Aaj vrat hai'."

#### F-5.2-04 — Dislikes have no engine behaviour
- Severity: Major
- Where: FR-M6 (p.6); §6.1 (p.14)
- Quote: "Free-text dislikes and allergies" (p.6)
- Problem: §6.1 has no dislike rule, so "no baingan" either does nothing (users notice at once) or gets treated like an allergy.
- Fix: Add to §6.1 after Allergy: "Dislike | Recipe's main ingredient (`is_main`) is disliked | No, 'Unko <x> pasand nahi'" and "Dislike (minor) | Disliked item is optional or garnish | Tweak, 'Unki katori mein <x> mat daalo'". Dislikes are picked from the Ingredient catalogue with free-text fallback. AC: "A member who dislikes baingan sees baingan bharta as No."

#### F-5.2-05 — The needs list misses common Indian health and household needs
- Severity: Minor
- Where: FR-M4 (p.6)
- Quote: "Needs (multi-select): Low oil, Low" … "sugar, High protein, No maida, Kid-"
- Fix: Add Low salt (blood pressure), Gluten-free, Soft food (elders, dentures). Make Kid-friendly auto-on when `is_kid` so the two do not diverge. Copy rule: "Health-related needs are preferences, not medical advice (§7.3)."

#### F-5.2-06 — Member cap and removal
- Severity: Minor
- Where: FR-M1 (p.6)
- Quote: "Add, rename and remove members" … "(max 12)"
- Fix: "Max 20 members (performance-tested at 20). Removing a member archives the profile: it drops out of ranking and coverage; history and ratings remain." Joint families and regular domestic staff who eat at home can exceed 12.

### 5.7 Home (§5.3)

#### F-5.3-01 — Three fixed slots miss evening snacks and tiffin; boundary times undefined
- Severity: Major
- Where: FR-H1 (p.6); §8 Menu.slot (p.18); §13 (p.24)
- Quote: "Default meal slot by device time:" … "Nashta before 11:00, Lunch 11:00" … "16:00, Dinner after 16:00"
- Problem: Many households also cook shaam ka nashta with chai and pack tiffin in the morning, often by the same cook in the same shift. Whether 11:00 and 16:00 are inclusive, what slot 00:30 maps to, and which clock applies (device vs IST; §8 has no timezone) are undefined.
- Fix: FR-H1: "Slots: Nashta, Lunch, Dinner (Must). Tiffin and Shaam ka nashta are optional slots, off by default, enabled in settings (**Should**). Defaults by household time: Nashta 04:00–10:59, Lunch 11:00–15:59, Shaam 16:00–18:29 (if enabled), Dinner 18:30–03:59; times after 00:00 belong to the previous date's Dinner." Add `Household.timezone` (default Asia/Kolkata). AC: "At 00:30 on 5 Oct, Home shows Dinner for 4 Oct."

#### F-5.3-02 — The Home top-8 has no variety rule, and the pick may repeat in the grid
- Severity: Minor
- Where: FR-H2, FR-H3 (p.6); FR-F6 (p.13)
- Quote: "the top-ranked dish for the slot" | "dish within 3 days unless asked"
- Fix: FR-H3 AC: "The grid excludes the pick. At most 2 recipes from the same `dish_category` (dal, sabzi, rice, roti/paratha, curry, snack, sweet). FR-F6 applies to Home and chat. Pull-to-refresh shows the next 8."

#### F-5.3-03 — Header constraints and sticky bar scope
- Severity: Minor
- Where: FR-H5, FR-H6, FR-H7 (p.7)
- Quote: "Max 3 constraints shown" | "Sticky menu bar appears once one" | "Rotation every 2.5 s"
- Fix: H7: "Priority: allergy > Jain/no-onion-garlic > veg/egg > vrat today > health needs; '+N more' opens S2." H6: "Counts dishes for the selected slot and date." H5: "Rotation pauses under reduce-motion or a screen reader."

#### F-5.3-04 — Home ranking does not state that it avoids the LLM
- Severity: Minor
- Where: §5.3 (p.6–7); §9.1 `/recommendations` (p.20)
- Quote: "Ranked recipes with fit summaries"
- Fix: "Home recommendations use the matching engine and FR-F5/F6 signals only; no LLM call. The 'Maharaj ka pick' caption is a template." Otherwise the 1.5 s budget and LLM cost break.

#### F-5.3-05 — Health constraints in the Home header are visible to anyone holding the phone
- Severity: Minor (new; raised by the Opus review)
- Where: FR-H7 (p.7); §10 Privacy (p.22)
- Quote: "and key constraints (e.g. "Dadi" … "(Jain) … Papa (low sugar)")"
- Problem: The FRD classes health-like tags as personal data, then prints "Papa (low sugar)" in the header of a screen a family cook in mode-switching, a child, or a guest holding the phone will see. Related to F-5.7-05 but on the family side.
- Fix: "The header shows diet constraints by default (Jain, veg, allergies). Health needs appear only if the member (or admin for profile-only members) sets 'Show on Home'; otherwise the header shows '+1 need'."

### 5.8 Maharaj chat (§5.4)

#### F-5.4-01 — Chat ownership and visibility undefined
- Severity: Major
- Where: FR-C5, FR-C7 (p.7); §8 ChatSession (p.19)
- Quote: "Chat history saved for 30 days"
- Problem: ChatSession belongs to the Household. Whether a teenager sees Papa's chats, whether a hired cook can chat, whether history is per user, and whether context includes other users' turns are all undefined.
- Fix: FR-C7: "Chat sessions are per user and private to that user; the admin cannot read other members' chats. Hired cooks have no chat in v1. Context (FR-C5) uses only the current user's session. History is kept 30 days, then hard-deleted, including at the LLM vendor (F-7-02)." Add `ChatSession.user_id`.

#### F-5.4-02 — Latency targets have no per-stage budget for a two-LLM-call pipeline
- Severity: Major (wording softened per the Opus review: the 8 s timeout bounds the tail; the real gap is the missing budget)
- Where: FR-C3 (p.7); §7.1 (p.15); §10 Reliability (p.22)
- Quote: "First token in under 2 s, full reply in" … "under 6 s (p90)" (p.7) | "fails or times out after 8 s" (p.22)
- Problem: The first visible token needs Parse (LLM call 1), Retrieve, Rank, and the first token of Write (LLM call 2). Under 2 s is aggressive with no per-stage budget, no separate timeout per call, and no fallback for the Write step.
- Fix: Add to §7.1: "Budgets (p90): Parse 1.2 s (timeout 2.5 s, then rule-based parser); Retrieve + Rank 300 ms; Write first token 500 ms (timeout 3 s, then a template reply from the ranked results). Cards go to the client as soon as Rank finishes, before Write." §10: "LLM timeouts: parse 2.5 s, write 3 s." FR-C3 AC: "Cards visible in under 2.5 s; full reply under 6 s (p90) on 4G."

#### F-5.4-03 — "Session" and "same intent" undefined
- Severity: Minor
- Where: FR-C5, FR-C1 (p.7)
- Quote: "Keep conversation context within a" | "Same query in all three returns the"
- Fix: C5: "A session ends after 30 min without a message, or on a slot change." C1 AC: "On a 200-query golden set (each intent in English, Devanagari and Hinglish, with spelling variants such as sabzi/sabji, bhindi/bhendi), parsed filters match in at least 95% of cases. Parse runs at temperature 0."

#### F-5.4-04 — "Closest options" could surface unsafe dishes
- Severity: Minor
- Where: FR-C6 (p.7)
- Quote: "When nothing matches, say so and" | "show the closest options"
- Fix: "Closest = relax soft filters in §7.1 order. Recipes that are No for any eater because of allergy, or No for the `member_focus` member, are never shown. The message names the dropped filters."

### 5.9 Recipe detail (§5.5)

#### F-5.5-01 — "Household size" is undefined and recipes have no base servings
- Severity: Major
- Where: FR-R3 (p.8); §8 Recipe, Household (p.18)
- Quote: "Ingredients list with quantities," … "scaled to household size"
- Problem: Scaling needs a base, and `Recipe` has no `base_servings`. The target could be member count, `Household.default_servings`, today's eaters, or eaters with kids as half; each gives different quantities. S3, P3 and S5 inherit the answer.
- Fix: Add a §5.0 Glossary: "Servings = adult-equivalent portions: adult 1.0, kid (`is_kid`) 0.5, plus guests. Recipe detail uses `Household.default_servings` unless opened from a menu or ticket, in which case it uses that ticket's servings." Add `Recipe.base_servings` (required). AC: "4 adults + 2 kids scales a base-4 recipe by 1.25, rounded per FR-R3."

#### F-5.5-05 — Recipe scaling is not linear: salt, spices, oil and cooking times do not scale with servings
- Severity: Major (new; raised by the Opus review)
- Where: FR-R3 (p.8); FR-K5 (p.9); FR-S3 (p.11)
- Quote: "Ingredients list with quantities," … "scaled to household size" (p.8) | "Cook opens any dish's recipe," … "scaled to the ticket's servings" (p.9)
- Problem: R3, K5 and S3 all scale quantities to servings, and the FRD implies simple multiplication. Salt, chilli, whole spices, tempering oil, water in pressure cooking, cooking time and the number of whistles do not scale linearly. Naive scaling produces over-salted, over-spiced food for 8 and wrong K5 audio instructions ("4 whistles" becomes "8 whistles"). The cook will be blamed, and the ratings (F5) will learn from it.
- Fix: FR-R3 addition: "Each ingredient carries a scaling rule from `Ingredient.scaling_rule` ∈ {linear, sublinear (×0.75 per doubling, for salt, chilli, whole spices, tempering oil, ghee), fixed (tadka items, whistles, cooking time)}. Steps that mention a time, count or whistles are written with placeholders that scale by the step's own rule or stay fixed. Above 3× base servings, show 'Do batch mein banayein' instead of scaling." AC: "Scaling a base-4 dal to 8 shows 1.5× salt and the same whistle count; the K5 audio reads the scaled values."

#### F-5.5-02 — Fit labels differ between engine, Recipe detail and prototype
- Severity: Nit
- Where: FR-R2 (p.8); §6 intro (p.14)
- Quote: "Perfect / Tweak / Nahi and a reason" (p.8) | "the engine returns Fit, Tweak or No, plus one reason" (p.14)
- Fix: "Engine values: fit / tweak / no. Display labels: Perfect / Tweak / Nahi on all surfaces."

#### F-5.5-04 — The "3–10 steps" AC fails for common dishes
- Severity: Minor (split out of F-5.5-02 so it is not lost under a Nit)
- Where: FR-R4 (p.8)
- Quote: "Numbered steps" … "3…10 steps"
- Problem: Biryani, undhiyu, puran poli, dhokla and most sweets need more than 10 steps, so the AC would fail a real share of the 1,000-recipe catalogue or force unreadably long steps.
- Fix: R4 AC: "3–15 numbered steps; each step at most 2 sentences; sub-recipes (masala paste, dough) may be nested."

#### F-5.5-03 — The "Video recipe" button when the source has no video
- Severity: Minor
- Where: FR-R5 (p.8); §7.4 (p.16)
- Quote: ""Video recipe" opens the source" | "The "Video recipe" link must point to the"
- Fix: "Show 'Video recipe' only when `Recipe.video_url` is set; otherwise 'Source'. A weekly link checker hides dead links."

### 5.10 Day menu and sharing (§5.6)

#### F-5.6-02 — One action, three names, and no step to pick the assignee
- Severity: Major
- Where: FR-P4 (p.8); FR-K2 (p.9); §9.1 `/menus/{id}/confirm` (p.20); §2 Rotates (p.2)
- Quote: ""Send to cook" turns the menu into" … "a cooking ticket in the cook app" (p.8) | "Each ticket has an assignee chosen" (p.2)
- Problem: "Send to cook", "confirms a meal's menu" and `confirm` may be one action or several; it is unclear whether adding a dish auto-confirms. For Rotates and Both the assignee must be chosen at confirm, but S8's actions do not include it. In the Family-cooks setup there is no one to "send" to.
- Fix: FR-P4: "'Confirm menu' (label per setup: 'Cook ko bhejo' for hired, 'Plan pakka karo' for family) creates the ticket. The confirm sheet shows eaters (FR-P7), due time (FR-K2a) and assignee (pre-filled from the primary cook, editable). AC: one tap creates exactly one ticket per menu; confirming again edits the same ticket (FR-K7)."

#### F-5.6-03 — A WhatsApp-only cook breaks the ticket lifecycle; "without a smartphone" is the wrong condition
- Severity: Major
- Where: FR-P4 (p.8); §13 Assumptions (p.24)
- Quote: "(WhatsApp message only if the" … "cook has no app)" (p.8) | "WhatsApp is only a fallback for a hired cook without a smartphone." (p.24)
- Problem: WhatsApp needs a smartphone, so the condition is wrong. More importantly, a ticket sent by share sheet can never be Accepted or Completed by the cook: no rating prompt (F1), no stock decrement (S4), no cooked history (F6), nothing in "tickets completed on time", and edits must be re-shared by hand.
- Fix: Add **FR-P8 Must**: "Cook mode 'WhatsApp-only' (no app): on confirm, the app opens the share sheet with a Hindi/Hinglish ticket text (dishes, servings, eaters, tweaks, due time). The ticket is admin-managed: the admin marks Accepted/Completed from the ticket card, and 30 min after `due_at` the app asks the admin 'Khaana ban gaya?'. Edits prompt a re-share with 'Badlav:' lines." §13: "for a hired cook who does not use the app".

#### F-5.6-04 — Three parallel stock states with no reconciliation
- Severity: Major
- Where: FR-P3 (p.8); FR-S2, FR-S3 (p.11); §8 PantryItem, Ticket.required_items (p.18–19)
- Quote: "Checkboxes persist per menu" (p.8) | "Each item has a stock level: In" (p.11) | "every ingredient of every" (p.11)
- Problem: The grocery-list checkboxes (P3), pantry levels (S2) and ticket required-item statuses (S3) all describe "do we have it" with no link. It is unstated whether the grocery list pre-ticks In-stock items, whether ticking sets the pantry level, or whether P5 and S5 are the same list. Users will see contradictions in the same session.
- Fix: "The pantry (PantryItem.level) is the single source of truth. The menu grocery list is a view: In-stock items pre-ticked, Low/Out unticked. Ticking sets the item In stock (logged with updated_by). P5 'Order missing items' is a ration request created by the admin and pre-approved (FR-S6). `required_items.stock_status` is read from the pantry at render time, not stored." AC: "Changing a pantry level updates the grocery list and ticket required items within 5 s."

#### F-5.6-05 — Concurrent editing of one menu
- Severity: Minor
- Where: FR-P1 (p.8)
- Quote: "One menu per household per meal" | "Adding the same dish twice is"
- Fix: "Menu changes are per-dish operations (add/remove), not a whole-menu PUT; the server merges. A remove after confirm is a ticket edit (FR-K7). AC: two members adding different dishes within 1 s both see both."

#### F-5.6-06 — Bill list uses recipe units, not purchase units
- Severity: Minor
- Where: FR-P5 (p.8)
- Quote: "bill-style list of unchecked items" | "(item, quantity, unit); the admin"
- Fix: "Bill quantities convert to purchase units via `Ingredient.purchase_unit` and pack size (toor dal → 500 g), rounded up; loose produce in grams or pieces." "1.5 cup toor dal, 2 tsp jeera" is not what a kirana shop sells.

### 5.11 Cook app and daily tickets (§5.7)

Blockers F-5.7-01, F-5.7-02, F-5.7-03 and F-5.7-06 are in §4.

#### F-5.7-12 — A hired cook who simply does not turn up has no escalation
- Severity: Major (new; raised by the Opus review)
- Where: FR-K8, FR-K10, FR-K11, FR-K12 (p.10); §5.7 (p.8–11)
- Quote: "Cook toggles On duty / Off duty," (p.10) | "If nobody else can cook, Maharaj" (p.10)
- Problem: The FRD assumes cooks toggle Off duty themselves. The most common real failure is a cook who neither toggles nor accepts: a New ticket sits unaccepted until lunch, or an Accepted ticket is never started. Nothing escalates. F-5.7-11's trigger (Unassigned 2 h before due) does not cover it because the ticket still has an assignee.
- Fix: Add **FR-K22 Must**: "Escalation: a New ticket not Accepted by `due_at` − 2 h (Nashta: − 1 h), or an Accepted ticket not in Cooking by `due_at` − 45 min, alerts the admin and the backup cook ('Ramesh ji ne abhi tak accept nahi kiya'). The admin can reassign in one tap, mark the cook Off duty for today, or trigger FR-K12. Thresholds are household settings." AC: "In a scripted test, an unaccepted lunch ticket raises the alert at exactly `due_at` − 2 h and appears in the admin's Unassigned/at-risk list."

#### F-5.7-04 — "Hindi-first" cook mode assumes a North Indian cook; `Cook.languages[]` is unused
- Severity: Major
- Where: §2 Hired cook (p.2); §4 Cook app screens (p.4); §8 Cook.languages (p.18); §10 Language (p.22)
- Quote: "Separate Hindi-first cook mode" (p.2) | "UI copy in Hinglish (default), English and Hindi; all" (p.22)
- Problem: The recipe coverage is pan-Indian (220 South, 130 East), but the cook side is Hindi-only. Cooks in Chennai, Bengaluru, Hyderabad, Kolkata and Guwahati often do not read Hindi. `Cook.languages[]` exists in the model but no requirement uses it, and no regional language appears even under Later.
- Fix: FR-K1 addition: "Cook mode language is chosen at cook onboarding (v1: Hindi, Hinglish, English). The ticket's WhatsApp text uses the same language." Later: "Cook mode and recipe steps in Tamil, Telugu, Kannada, Bengali, Marathi (order by sign-up city data)." §10: "All cook-facing strings and recipe steps are keyed by locale from day one."

#### F-5.7-05 — The hired cook sees family members' health-like data through tweaks
- Severity: Major
- Where: FR-K1, FR-K4 (p.9); §10 Privacy (p.22)
- Quote: "Cook cannot edit member profiles" (p.9) | "Ticket lists per-member tweaks" (p.9)
- Problem: The FRD classes diet, allergy and health-like tags as personal data, then shows tweaks derived from them ("Papa (low sugar)", diabetic) to an employee outside the family, with no notice or choice.
- Fix: FR-K4 addition: "Tweaks shown to a hired cook state the action, not the reason ('Papa: bina cheeni', not 'Papa (diabetic)'). Member notes marked private are never shown in cook mode. Onboarding tells the admin: 'Cook ko sirf banane ki hidayat dikhegi.' AC: no health-need label appears in any hired-cook API response."

#### F-5.7-08 — Push delivery time is not controllable; "what changed" undefined
- Severity: Minor
- Where: FR-K3 (p.9)
- Quote: "Arrives within 10 s; ticket shows" | ""Updated" tag with what changed"
- Fix: AC: "Push dispatched to FCM/APNs within 10 s (server log); K1 refreshes within 10 s when open. 'Updated' lists added/removed dishes and changed servings, due time, eaters and notes as 'Pehle → Ab' lines." FCM/APNs delivery and battery savers are outside the team's control.

#### F-5.7-09 — Chef for the day: permissions, arbitration and midnight
- Severity: Minor
- Where: FR-K15–K17 (p.11)
- Quote: "Any member with the app can" | "the first claim wins and the second" | "automatically at midnight or when"
- Fix: K15: "Only Unassigned, New or Accepted tickets can be claimed; claiming a hired cook's Accepted ticket needs admin approval." K16: "Claims are atomic (compare-and-set on ticket version)." K17: "Ends at the later of midnight and completion of claimed tickets; the admin can release any claim."

#### F-5.7-10 — No off-boarding for a hired cook
- Severity: Major
- Where: FR-K1 (p.9); §5.7 (p.8–11)
- Quote: (absent — nearest text: "Admin gives the cook role to a")
- Problem: Cooks leave often. Open tickets, the cook's login and sessions, ratings history and access to household data after removal are all undefined.
- Fix: Add **FR-K21 Must**: "Admin can remove a cook. Sessions are revoked immediately. Open tickets go to the backup or Unassigned (F-5.7-06). Ratings and cooked history are kept, attributed by name, and no longer visible to the cook. AC: after removal, the cook's token returns 401 on every endpoint within 1 min."

#### F-5.7-11 — "If nobody else can cook" has no trigger
- Severity: Minor
- Where: FR-K12 (p.10)
- Quote: "If nobody else can cook, Maharaj" | "dishes, ready-to-cook items in"
- Fix: "Trigger: a ticket is Unassigned 2 h before `due_at`, the FR-K22 escalation fires with no backup, or the admin taps 'Aaj koi nahi banayega'. Suggestions: recipes ≤ 15 min with all tracked ingredients In stock, staples in a new 'Ready-to-cook' category, plus a static 'Order in' card."

### 5.12 Kitchen stock and ration (§5.8)

Blocker F-5.8-01 is in §4.

#### F-5.8-02 — Stock decrement has no quantities or thresholds
- Severity: Major
- Where: FR-S2, FR-S4 (p.11); §8 PantryItem, Staple (p.18–19)
- Quote: "Completing a ticket lowers stock" … "estimates for used items" | "Items crossing a threshold turn" | "stock / Low / Out, with an optional"
- Problem: Quantity is optional (cooks will not enter it), so there is nothing to lower and no threshold to cross. Staple has no threshold or pack-size field. S4 is not implementable as written.
- Fix: FR-S4 (**demoted to Should**, F-3-01): "If PantryItem.qty is set, subtract the ticket's required qty; at ≤ `Staple.low_threshold` set Low; at ≤ 0 set Out. If qty is not set, after Completed ask the cook one question: 'Inme se kya khatam hone wala hai?' listing the ticket's tracked items (one tap each). AC: no pantry level changes without either a qty calculation or a human tap." Add `Staple.low_threshold, default_pack_qty`.

#### F-5.8-03 — Catalogue edits: permission, custom items, deletion
- Severity: Minor
- Where: FR-S1 (p.11)
- Quote: "staples catalogue; admin or cook" | "removes what they never use"
- Fix: "Admin and family cooks can hide or add items; a hired cook can only suggest. Custom items: name, category, unit. Hiding keeps references on existing tickets and requests."

#### F-5.8-04 — Family cook "approves her own ration list", but S6 says the admin approves; no partial purchase
- Severity: Minor (approval side resolved by the F-2-02 table)
- Where: §2 Family cooks (p.2); FR-S6, FR-S7 (p.12)
- Quote: "she approves her own substitutes and ration list" (p.2) | "Admin approves, edits or rejects a" (p.12)
- Fix: FR-S6: "Per the §2.1 table: a family cook's request is auto-approved and the bill goes to the admin (or whoever buys)." FR-S7: "'Bought' is per item; unbought items stay Pending. Anyone who can approve can mark Bought."

### 5.13 Out-of-stock handling (§5.9)

#### F-5.9-01 — Substitutions need a source; "the LLM never invents ingredients" rules the LLM out
- Severity: Major
- Where: §5.9 steps 2–3 (p.12); §7 intro (p.15); §9.2 LLM use (p.21); FR-O2 (p.13)
- Quote: "suggest a safe swap (e.g. tomato" … "puree for fresh tomatoes)" (p.12) | "The LLM never invents recipes," (p.15)
- Problem: §9.2 lists "out-of-stock alternates" as an LLM task, yet §7 forbids the LLM from inventing ingredients, and no curated substitution data exists. An LLM-proposed swap (peanuts for cashews in a gravy) could break an allergy; O2 enforcement only works if the engine re-checks the substituted ingredient list.
- Fix: Add entity `SubstitutionRule {from_ingredient_id, to_ingredient_id, ratio, applies_to_tags[], note_hi}` (content-curated, ~300 rules at launch). Step 3: "Swaps come only from SubstitutionRule; the LLM only chooses among and phrases valid candidates." FR-O2 AC: "The engine re-evaluates every eater against the substituted ingredient list; any new No removes the candidate."

#### F-5.9-03 — The timeout clause is ambiguous
- Severity: Minor
- Where: §5.9 step 6 (p.12)
- Quote: "If nobody answers within 30 min of the due time"
- Fix: "If no approver responds within min(20 min, time until `due_at` − 15 min), the cook may use the top suggestion; the ticket records 'auto-approved (timeout)'." A stock issue at 13:20 for a 13:30 lunch cannot wait 30 min.

#### F-5.9-04 — 5 s suggestions against an 8 s LLM timeout
- Severity: Minor
- Where: FR-O1 (p.12); §10 Reliability (p.22)
- Quote: "Suggestions appear within 5 s of an" (p.12) | "fails or times out after 8 s" (p.22)
- Fix: "Steps 2–4 candidates come from the engine (alt_recipe_ids, SubstitutionRule, ranking) within 2 s. The LLM only phrases the note, 2 s timeout, template fallback. AC: 5 s p95 including network."

#### F-5.9-05 — The creation-time stock check is unspecified
- Severity: Minor
- Where: §5.9 step 1 (p.12)
- Quote: "or the stock check at ticket creation" | "finds one."
- Fix: "At confirm, Out tracked items are shown on the confirm sheet ('Dahi khatam hai — phir bhi bhejein?'). If confirmed anyway, the ticket gets `stock_issue_open` and §5.9 runs. Low items show a warning only."

#### F-5.9-06 — "Same dish, different recipe" needs content that is not planned
- Severity: Minor
- Where: §5.9 step 2 (p.12); §7.4 (p.16); §8 Recipe.alt_recipe_ids (p.18)
- Quote: "Same dish, different recipe. Maharaj searches for an alternate recipe of the same dish"
- Fix: Add `Recipe.dish_group_id`. §7.4: "At least 150 of the top 300 dishes have a variant in the same dish_group." Step 2: "using no Out items; untracked items are assumed available."

### 5.14 Ratings and learning (§5.10)

#### F-5.10-01 — Named ratings shown to the hired cook
- Severity: Major
- Where: FR-F3 (p.13)
- Quote: "Cook sees each rating with the" … "member's name, tags and note on"
- Problem: A cook who sees "Bahu: 1 star, zyada teekha" by name gets pulled into family dynamics. Members will then rate dishonestly, which defeats F5 learning. The FRD protects family cooks (appreciation-first) but not hired cooks.
- Fix: FR-F3: "The hired cook sees per-dish averages, tags and notes without names by default; the admin can turn on 'Show names to cook'. AC: with the default, no member name appears in any hired-cook ratings API response."

#### F-5.10-02 — Learning rules are not specified enough to build or test
- Severity: Major
- Where: FR-F5 (p.13); §6.2 (p.15)
- Quote: "for 30 days; repeated tags propose" | "a tweak (e.g. "Papa: kam namak")" | "that the admin confirms"
- Problem: "Ranks higher" has no weight and §6.2 has no learning term. "Repeated" has no count or window. What a confirmed tweak does (change spice, add a note, add a need) is unstated.
- Fix: Add `L(e,r)` to §6.2 (F-6-05). FR-F5 AC: "Tweak proposal (**Could**, F-3-01) after the same tag from the same member on 3 of their last 5 ratings within 30 days. On confirm it becomes a standing member note shown on every ticket. Nothing changes diet or spice without admin confirmation."

#### F-5.10-03 — The 3-day no-repeat rule fights everyday food
- Severity: Minor
- Where: FR-F6 (p.13)
- Quote: "dish within 3 days unless asked"
- Fix: "Applies to `dish_category` in {curry, sabzi, special, snack}. Staples (dal, rice, roti) repeat freely, but the same dal recipe is penalised within 2 days. 'Unless asked' = the user named the dish or tapped 'Phir se banao'."

#### F-5.10-04 — Rating prompts, proxy ratings and opting out
- Severity: Minor
- Where: FR-F1, FR-F2 (p.13); §5.10 (p.14); §8 Rating (p.19)
- Quote: "30 min after Completed, each eater" | "Admin can rate on behalf of" | "She can turn ratings off from her own settings."
- Fix: F1: "Prompts respect quiet hours 22:00–07:00 (deferred to 08:00)." F2: "Any adult member can rate for profile-only members." Add `Rating.rated_by_user_id`. Ratings-off: "Hides ratings from the family cook's view only; prompts and F5 learning continue."

### 5.15 Family-fit matching engine (§6)

#### F-6-01 — "Recipe not tagged" rules make almost everything a Tweak
- Severity: Major
- Where: §6.1 Low sugar, Low oil, High protein rows (p.14); §6.2 badges (p.15)
- Quote: "Recipe not tagged low-sugar" | "Recipe not tagged low-oil" | "Recipe not tagged protein" | "Sabke liye   Everyone is Fit"
- Problem: Most recipes will not carry `low_sugar`, `low_oil` or `protein`. Any household with one Low-sugar Papa or one gym-going son gets Tweak on nearly every dish. "Sabke liye" becomes unreachable, the +3 Fit bonus stops separating recipes, and every ticket fills with generic tweaks ("Portion chhota, salad zyada" on plain moong dal). The rows also omit the member condition.
- Fix: Use contra-tags and apply the protein rule to the menu, not the recipe:

| Rule | Condition | Result | Reason |
|---|---|---|---|
| Low sugar | Member has Low sugar AND recipe tagged `sweet` or `high_sugar` | Tweak | Portion chhota, salad zyada |
| Low oil | Member has Low oil AND recipe tagged `fried` or `rich` | Tweak | Kam tel mein banao |
| Low salt | Member has Low salt AND recipe tagged `salty` | Tweak | Unka namak alag |
| High protein | Member has High protein AND slot ∈ {Lunch, Dinner} AND the menu has no `protein` dish | Tweak on the menu | Saath mein dahi/paneer |
| Kid-friendly | Member is kid AND spice ≥ 2 AND not `kid` | Tweak | Bachche ke liye alag, halka |

Recipes tagged `low_sugar`, `low_oil` or `protein` get +2 per matching member in §6.2. Content check (not a requirement): report the share of the launch catalogue that is "Sabke liye" for a fixture household with one Low-sugar member, and tune the tags until it is reasonable.

#### F-6-02 — The ticket example serves Dadi a Jain portion "alag", but the engine says No
- Severity: Major (the Opus review argued Blocker; kept Major because the fix is an added tag and rule, and the build can start without it, but it must be settled before content tagging begins)
- Where: FR-K4 (p.9); §6.1 Jain rule (p.14)
- Quote: "(e.g. "Dadi: bina pyaaz-lahsun katori" (p.9) | "Member is Jain and recipe is not Jain-" (p.14)
- Problem: Real kitchens routinely take out a Jain or no-onion-garlic portion before the tadka; the K4 example assumes that. The engine, however, returns No for any non-Jain-safe recipe, so this tweak can never be generated. The two sections describe different products.
- Fix: Add the recipe flag `jain_adaptable` (Jain-safe if the onion/garlic/root-veg items are left out before a given step; `adapt_step` stored). Rule: "Member is Jain (or No onion-garlic) AND recipe not safe AND `jain_adaptable` → Tweak, 'Pyaaz-lahsun se pehle unki katori alag nikaalo (step N)'. Otherwise No with the specific reason." AC: "The K4 example is producible from engine output."

#### F-6-03 — The Veg rule omits fish, and rule order produces wrong reasons
- Severity: Minor
- Where: §6.1 Veg, Egg, Jain rows (p.14)
- Quote: "Member is Veg and recipe contains" … "egg or meat" | "meat or fish"
- Fix: Write diet rules against derived flags in this order: Allergy → meat/fish → egg → non-veg exclusions (F-5.2-01b) → Jain/no-onion-garlic (F-6-02) → No maida/gluten → Dislikes → Tweaks. Read literally, Veg does not exclude fish, and Jain-first ordering makes chicken curry say "Pyaaz-lahsun hai".

#### F-6-04 — Spice matrix only implicit
- Severity: Nit
- Where: §6.1 Spice rows (p.14)
- Quote: "Member is Kam and recipe spice = 3"
- Fix: Add the 3×3 grid. Kam: 1 Fit, 2 Fit, 3 Tweak. Medium: all Fit. Teekha: 1 Tweak, 2 Fit, 3 Fit.

#### F-6-05 — The score ignores eaters, learning, repetition and stock
- Severity: Major
- Where: §6.2 (p.15); FR-F5, FR-F6 (p.13); §7.2 member_focus (p.16)
- Quote: "members who can eat it (Fit or Tweak) + 3" | "whose favourite cuisine matches - 15 if anyone is No"
- Problem: F5 (ratings), F6 (repeats), eaters (F-5.6-01) and stock (FR-K12, §5.9) all promise ranking effects that the only published formula does not contain. Implementers will each add their own terms, and "deterministic" will not hold across Home and chat.
- Fix: Replace §6.2 with: `Score(r) = Σ over eaters e [ 10·can(e,r) + 3·fit(e,r) + 2·fav(e,r) + 2·need_bonus(e,r) + L(e,r) ] − 15·anyNo(r) − Rep(r) + Stock(r)`, where `L(e,r)` = +4 if e rated r 4–5 in the last 90 days, −8 if 1–2 in the last 30 days; `Rep(r)` = 25 if cooked within the F6 window; `Stock(r)` = +3 if all tracked ingredients In stock, −5 per Out tracked ingredient. `member_focus` is a filter, not a weight. Ties: shorter `minutes`, then `recipe_id`. AC: "Given a fixture household and catalogue, the top 8 is identical across 100 runs and across `/recommendations` and `/chat`."

#### F-6-06 — The tag set is missing safety and India-specific tags, and has undefined ones
- Severity: Major
- Where: §6.3 (p.15)
- Quote: "tags from this set: low_oil," … "low_sugar, protein, kid, light, rainy, special, maida."
- Problem: The engine needs allergens, `root_veg`, `onion_garlic`, meat type, `vrat_ok`, `jain_adaptable`, `sweet`, `fried`, `salty`, `gluten`, `dairy` and `dish_category`, none listed. `light`, `rainy` and `special` have no criteria, so two taggers will disagree.
- Fix: Split tags into (a) **derived** from Ingredient flags, computed by code, never hand-set: diet, jain_safe, allergens, onion_garlic, root_veg, meat_type, gluten, dairy; and (b) **editorial**, with written criteria in a Tagging Guide appendix: light, rainy, special, kid, sweet, fried, salty, vrat_ok, jain_adaptable, dish_category. AC: "Inter-tagger agreement ≥ 90% on a 100-recipe audit sample before launch."

#### F-6-07 — FitCache invalidation and badge arithmetic
- Severity: Minor
- Where: §8 FitCache (p.19); §6.2 badges (p.15)
- Quote: "fit result and reason" (p.19) | "X/Y ke liye  At least one member is No" (p.15)
- Fix: "FitCache key = (member_id, recipe_id, member_profile_version, recipe_version, date if a diet-day rule applies). Badge: X = eaters who are Fit or Tweak; Y = eaters."

### 5.16 Maharaj AI assistant (§7)

#### F-7-01 — Hard vs soft filters undefined
- Severity: Major
- Where: §7.1 step 2 (p.15)
- Quote: "hard filters first, then keyword" | "drop soft filters one at a time"
- Problem: Whether `max_minutes`, cuisine, slot, `light` or `member_focus` is hard or soft, and the drop order, are unstated; results and the "which were dropped" message will vary by implementer.
- Fix: "Hard (never dropped): eater No rules, slot, member_focus, explicit exclusions ('paneer nahi'). Soft, dropped in this order: keywords → cuisine → tag → max_minutes (relaxed +15 min, then removed). The reply's first line names each dropped filter."

#### F-7-02 — Household personal data goes to a third-party LLM with no data-handling requirements
- Severity: Major (legal sign-off before launch)
- Where: §7.1 step 1 (p.15); §10 Privacy (p.22); §9.2 (p.21)
- Quote: "Send the query, the last 6 chat turns, the household profile and the current slot" (p.15) | "encrypted at rest, never sold, deletable with the" (p.22)
- Problem: The household profile includes names, children, diet, allergy and health-like tags, which the FRD itself calls personal data, sent to an external LLM on every query. Vendor retention, training use, region, a DPA and minimisation are unstated.
- Fix: Add to §7.1: "The LLM receives pseudonymous member keys (M1, M2 …) with diet, needs and relation labels, never phone numbers, and names only when the user typed them. Vendor terms: zero data retention (or ≤ 30 days), no training on customer data, a DPA. Vendor and region are listed in the privacy notice." AC: "A log audit of 1,000 LLM requests finds no phone numbers and no stored names beyond what the user typed."

#### F-7-03 — No cost cap, rate limit or prompt-injection handling
- Severity: Major
- Where: §7 (p.15–16); §9.2 LLM API (p.21)
- Quote: (absent — nearest text: "Chat falls back to the rule-based parser if the LLM")
- Problem: At ₹50 per week, one heavy user or a script erases a household's margin. Member names, dislikes, notes and cook messages are user text that flows into prompts; the engine protects the No rules, but the Write step could still produce false claims or off-topic content.
- Fix: Add NFR "AI cost and safety": "Max 60 chat queries per household per day and 10 per minute; beyond that, rule-based parser only. User-supplied text is passed as quoted data in a delimited field, never as instructions. Write output is validated (F-7-04). Off-topic requests get a fixed reply ('Main sirf khaane mein madad karta hoon')."

#### F-7-04 — The Write step has no guard or fallback
- Severity: Minor
- Where: §7.1 step 4 (p.15)
- Quote: "using only the ranked results and their fit data."
- Fix: "Post-validate: every dish name mentioned must be in the returned set; the everyone-count must equal the engine's; banned-phrase list (cure, diabetes-safe, weight loss). On failure, use the template reply."

#### F-7-05 — Intent mappings that will surprise users
- Severity: Minor
- Where: §7.2 (p.16)
- Quote: "jaldi, quick, 15 min, fast" … "max_minutes: 20" | "tiffin, bachchon ke liye, beti/daughter" | "mehmaan, guest, party, special"
- Fix: "Explicit numbers win: 'N min' → max_minutes N; words alone → 20. tiffin → new tag `tiffin` (packable), not kid. Relation words map only through member_focus. mehmaan → tag special + prompt for guest count (FR-P7). Add intents: exclude_ingredient (negations), servings ('4 log'), date (kal/parson)."

#### F-7-06 — Recipe licensing is contradictory, and the backend "talks to recipe sources"
- Severity: Major
- Where: §7.4 (p.16); §13 (p.24–25); §9 intro (p.19)
- Quote: "Recipes are gathered from publicly available sources." (p.16) | "Recipes come from a curated, licensed database, not live web scraping." (p.24) | "Do not scrape sites whose terms forbid it." (p.16)
- Problem: The assumption says "licensed", the decision says "publicly available, no paid partner", and §9 has the backend talking to recipe sources at runtime. Rewriting steps limits copyright risk for text, but photos, linking YouTube as "Video recipe" and AI-generated photos of named regional dishes need a policy.
- Fix: §13 assumption: "Recipes are curated offline from publicly available sources, rewritten in Banega's words, and stored in Banega's database. No runtime calls to recipe sites." §7.4: "A content policy signed off by legal before content work starts covers allowed sources, attribution, photo rights (AI-generated photos labelled) and a takedown process (72 h)." §9 intro: remove "recipe sources".

#### F-7-07 — Reply language vs the user's language setting
- Severity: Minor
- Where: §7.3 (p.16); §8 User.language (p.17)
- Quote: "Hinglish by default; switch to the language of the query when it is clearly English or"
- Fix: "Reply language = query language when detected with confidence ≥ 0.8; otherwise `User.language`. Hindi replies in Devanagari (F-11-01)." See also F-10-05.

#### F-7-08 — No minimum counts for restricted diets
- Severity: Minor
- Where: §7.4 coverage (p.17)
- Quote: "so each region has Jain," … "veg, egg and non-veg options where the cuisine allows."
- Fix: "Minimums across the 1,000: Jain-safe or jain_adaptable ≥ 200 (≥ 20 per slot), no-onion-garlic ≥ 250, vrat_ok ≥ 60, egg ≥ 80, kid ≥ 120; the content dashboard reports these per slot."

### 5.17 Data model (§8)

#### F-8-01 — A single `User.role` cannot represent the FRD's roles
- Severity: Major
- Where: §8 User (p.17)
- Quote: "hinglish), role (admin / member /" … "cook)" | "belongs to one Household"
- Problem: A family cook is both member and cook, the admin may be the cook, and Chef for the day is temporary cook authority. A single enum forces special-casing or wrong permission checks.
- Fix: `HouseholdMembership {user_id, household_id, is_admin, is_member, member_id?, cook_id?, status (invited / active / removed)}`. Permissions derive from the membership plus per-ticket Chef claims. AC: "One user can be admin, member and cook in the same household."

#### F-8-02 — Entities and fields required by FRs are missing
- Severity: Major (merges Builder's F-8-02 and F-8-03)
- Where: §8 (p.17–19)
- Quote: "Fifteen core entities (no Reward entity in v1)." | "household_id, date, slot (nashta /" … "lunch / dinner), recipe_ids[],"
- Problem: Invites (A3), ingredients beyond staples (F-5.8-01), substitution rules (F-5.9-01), device tokens and notification settings (K3, §9.2), chat messages with authorship (C5, C7), approvals and audit (§5.9 step 6), diet days (F-5.2-02) have nowhere to live. Fields for scaling, video, variants, aliases, timestamps for the on-time metric, proxy ratings, timezone and thresholds are absent.
- Fix: Add entities: HouseholdMembership (F-8-01); Invite {household_id, phone, role, token_hash, expires_at, used_at}; Ingredient (F-5.8-01); SubstitutionRule (F-5.9-01); DietDay {member_id or household_id, rule, weekdays[] or dates[]}; Device {user_id, platform, push_token, app_version}; NotificationPref {user_id, event, enabled, quiet_hours}; ChatMessage {session_id, author, text, recipe_ids[], filters}; Approval {ticket_id or ration_request_id, type, requested_by, decided_by, decision, decided_at, auto}. Add fields: Recipe.base_servings, video_url, dish_group_id, dish_category, name_hi, aliases[], version; Menu.eaters[], guests{}, due_at, assignee_id; Ticket.accepted_at, started_at, completed_at, completed_by, stock_issue_open, version; Rating.rated_by_user_id, unique (ticket_id, recipe_id, member_id); Household.timezone, enabled_slots[], slot_defaults{}; Staple.low_threshold, default_pack_qty; Member.gender?, archived_at; deleted_at on personal tables for the FR-A8 undo window.

### 5.18 APIs and integrations (§9)

#### F-9-01 — Endpoints are missing for existing FRs
- Severity: Major (the API table is the contract between the mobile and backend teams, and about ten FRs have no endpoint)
- Where: §9.1 (p.19–20)
- Quote: "/auth/otp, /auth/verify"
- Fix: Add: `/invites` (POST/GET/DELETE) and `/invites/{token}/accept` (FR-A3); `/devices` (POST/DELETE); `/me/notification-prefs` (GET/PUT); `DELETE /household`, `DELETE /me` (FR-A8); `/chat/sessions` (FR-C7); `/ingredients?q=`, `/staples`; `/menus/{id}/dishes` add/remove (F-5.6-05); `POST /tickets/{id}/transitions` (F-5.7-02); `/tickets/{id}/claim`, `/release` (Chef for the day); `/cooks/{id}/duty-history?month=` (FR-K13); `/webhooks/play`, `/webhooks/appstore` (FR-A7); `POST /demo` (FR-A4); `GET /approvals?status=pending`.

#### F-9-03 — External services table gaps
- Severity: Minor
- Where: §9.2 (p.21)
- Quote: "Per-role notification settings" | "temperature 0.3 for"
- Fix: Add rows: TTS (F-5.7-03), object storage + CDN for WebP variants, crash reporting. LLM notes: "Parse: temperature 0, JSON schema; Write: 0.3." Push: "Events per the notification matrix (F-X-01)."

### 5.19 Non-functional requirements (§10)

#### F-10-01 — Cook mode has no offline behaviour
- Severity: Major
- Where: §10 Offline (p.21)
- Quote: "Last Home list, open menu and grocery list" … "readable offline; chat shows "net nahi hai" and" … "queues nothing"
- Problem: Offline covers the family side only. Kitchens are often the worst-connected room, and cooks' phones run on low data packs. A cook who cannot open today's ticket or recipe mid-cooking, or whose "Completed" tap is lost, breaks ratings, stock and trust.
- Fix: "Cook mode offline read (**Must**): today's and tomorrow's tickets, scaled recipes, Hindi audio and required items are cached on open and on each push. AC: in airplane mode, the cook can open a ticket and read and play every step." "Offline write queue (**Should**): status changes, stock levels, Out marks and messages are queued and synced in order, with 'Bheja nahi gaya' indicators; server state wins for status."

#### F-10-05 — Regional languages on the family side: a Hinglish default alienates a third of the target catalogue's households
- Severity: Major (new; raised by the Opus review)
- Where: §10 Language (p.22); §7.3 (p.16); §7.4 coverage table (p.17)
- Quote: "UI copy in Hinglish (default), English and Hindi; all" (p.22) | "Hinglish by default; switch to the language of the query when it is clearly English or" (p.16)
- Problem: 350 of the 1,000 target recipes are South and East Indian, but the whole family UI is Hinglish, English or Hindi, with Hinglish as default and Hinglish-only Maharaj replies. F-5.7-04 covers the cook side; nothing covers Tamil, Kannada, Telugu, Malayalam or Bengali households on the family side, and a Hinglish default is a wrong first impression for them.
- Fix: §10 Language: "Default UI language is English when the device locale is not hi-IN; Hinglish and Hindi are selectable. Maharaj replies in the user's UI language when the query language cannot be detected (F-7-07). All family-side strings, recipe names and reason strings are keyed by locale." Later: "Family UI in Tamil, Telugu, Kannada, Bengali, Marathi, in the same order as cook mode."

#### F-10-03 — Accessibility omits text scaling and older users
- Severity: Minor
- Where: §10 Accessibility (p.22); §11.2 (p.23)
- Quote: "Touch targets at least 44 px; text contrast at least" (p.22)
- Fix: "Touch targets ≥ 48 dp (Android) / 44 pt (iOS). All screens support OS font scaling to 200% without clipping; minimum body 14 px (cook mode per F-4-04). Screen-reader labels exist in every UI language."

#### F-10-04 — Performance targets lack conditions; the Android floor may exclude cooks' phones
- Severity: Minor
- Where: §10 Performance, Platforms (p.21–22)
- Quote: "Home ready in under 1.5 s on a mid-range Android" | "iOS 16+ and Android 10+; phone portrait only in v1"
- Fix: "Reference device: [named ₹10–12k Android, 4 GB RAM]. Home: first 4 tiles ≤ 1.5 s warm, ≤ 3 s cold (p90, 4G). Devices below 4 GB or with reduce-motion get a static thali. Confirm Android 10 against cook-device survey data."

### 5.20 Design system and motion (§11)

#### F-11-01 — The chosen typefaces have no Devanagari
- Severity: Major
- Where: §11.2 (p.23); FR-C1 (p.7); §10 Language (p.22)
- Quote: "UI and body: Figtree 500"
- Problem: Bricolage Grotesque and Figtree are Latin-only. Hindi UI, Devanagari chat, Hindi recipe steps and cook mode will fall back to whatever system font the phone has; weights and metrics will mismatch, and truncation (FR-M7) will break differently per device.
- Fix: §11.2: "Devanagari companion: Noto Sans Devanagari (or Mukta / Hind) 500–800, sized +1 step relative to Latin, line height 1.5. Fonts are bundled. AC: every screen passes visual QA in Hindi at 100% and 200% text size."

#### F-11-02 — Token hygiene and motion cost
- Severity: Nit
- Where: §11 intro, §11.1, §11.4 (p.22–23)
- Quote: "(#095A29)" | "spinning once per 18 s"
- Fix: Add token `dhaniya-ledge #095A29`. "The Home thali animates for 6 s after Home opens, then rests; animations stop when backgrounded or under battery saver."

### 5.21 Analytics (§12)

#### F-12-01 — Events needed to run the product are missing
- Severity: Minor
- Where: §12 (p.23–24)
- Quote: "Track these events from day one; targets are set after the first 4 weeks of beta data."
- Fix: Add `chat_reply_completed` {first_token_ms, total_ms, parser, write_fallback, filters_dropped}; `invite_sent` / `invite_accepted`; `cook_onboarded`; `notification_opened`; `approval_decided` {minutes_to_decide, auto}; `subscription_renewal_failed`; `ticket_not_confirmed`; `cook_no_show_alert`. Day-one guardrails: crash-free sessions ≥ 99.5%, chat p90 ≤ 6 s, LLM fallback ≤ 5%.

#### F-12-02 — Analytics privacy rule covers names, not properties; metric wording
- Severity: Minor
- Where: §9.2 Product analytics (p.21); §12 (p.23–24)
- Quote: "slot, recipe_ids, fit_badges" | "share of days with at least one menu"
- Fix: "Events carry no member names, diets, allergies, needs or free text; fit data is aggregated per event. Household and user IDs are pseudonymous." Rename the metric to "share of days with at least one menu confirmed".

### 5.22 Decisions, assumptions and open questions (§13)

#### F-13-01 — Decisions and assumptions contradict the body; the open-questions list is too short
- Severity: Minor
- Where: §13 (p.24–25)
- Quote: "Do we need Hindi-script recipe steps for cooks who don't read English?"
- Fix: Resolve the three contradictions (F-7-06, F-5.6-03, F-5.7-03) in the body and remove them from §13. Replace "Still open" with a table (question | owner | needed-by | blocking FRs) seeded from report §9.

#### F-13-02 — "Voice-only cook mode not needed" is an untested literacy assumption
- Severity: Minor
- Where: §13 Decisions (p.25)
- Quote: "Voice-only cook mode" … "Not needed in v1"
- Fix: "Assumption: target hired cooks can read short Hindi or Hinglish labels. Validate with 10 cook usability sessions before beta; if fewer than 7 of 10 complete accept → cook → complete unaided, add icon-first ticket cards and audio read-out of the ticket summary (Should)."

### 5.23 Cross-cutting

#### F-X-01 — No notification matrix
- Severity: Major
- Where: §9.2 Push notifications (p.21); FR-K3, FR-K6, FR-K8, FR-K11, FR-S5–S7, FR-F1, FR-A6
- Quote: "New tickets, stock issues," | "rating prompts, off-duty" | "Per-role notification settings"
- Problem: Notifications are scattered across FRs, several events have no recipient (K6 messages, S5 requests, K11 unassigned, approvals, chef claims, trial reminders), and "per-role settings" has no FR. Users will get too many alerts or none, and QA has nothing to test against.
- Fix: Add §5.11 Notifications:

| Event | Recipients | Channel | Timing / rules |
|---|---|---|---|
| Ticket created / updated | Assignee | Push + K1 badge | Immediately; future-date tickets at 20:00 the day before |
| Ticket unassigned or at risk (FR-K22) | Admin, backup cook | Push | Immediately; repeat 2 h before due_at |
| Stock issue / approval needed | Eligible approvers (§2.1 table) | Push | Immediately |
| Cook message (K6) | Admin + confirmer of that menu | Push + Home card | Immediately |
| Ticket Completed | Eaters with app | Push (rating prompt) | +30 min, quiet hours respected |
| Ticket Not confirmed | Admin | Push ("Khaana bana?") | due_at + 3 h |
| Ration request sent | Admin | Push | Immediately |
| Ration approved / Bought | Cook | Push | Immediately |
| Cook off duty / on duty | Admin | Push + Home status | Within 10 s |
| Chef for the day claimed | Regular cook, admin | Push | Immediately |
| Low stock (S4) | Admin, cook | In-app only | Daily digest 18:00 |
| Trial day 5 / day 7 / expired | Admin | Push + banner | 10:00 IST |
| Weekly ration suggestion (S8) | Admin, cook | Push | Sunday 09:00 |

Every row can be switched off per user except approvals and ticket-assigned for the assignee. Quiet hours 22:00–07:00 by default.

#### F-X-02 — DPDP Act 2023 obligations are not addressed
- Severity: Major (legal sign-off before launch; the erasure part is the F-5.1-03 Blocker)
- Where: §10 Privacy (p.22); §2 (p.1–2); §7.1 (p.15)
- Quote: (absent — nearest text: "Diet, allergy and health-like tags are personal data:")
- Problem: Banega processes personal data of adults, children (profile-only kids created by a parent) and a hired cook (phone number, duty history "for salary later", ratings). Notice and consent, verifiable parental consent for children's data, purpose limitation, access and correction rights, a grievance mechanism and breach handling are all unspecified.
- Fix: Add NFR "Data protection (requires legal sign-off)": "Consent notice at sign-up in the UI language listing purposes (recommendations, cook tickets, AI processing by a named vendor). The admin confirms they are the parent or guardian when creating a kid profile. Each user can view and download their data and request erasure in-app (FR-A8). The cook gets their own notice at cook onboarding and can leave the household. A grievance contact is shown in settings. Breach process documented. Retention: chat 30 d; ratings and cooked history 2 y; deleted households purged from backups in 30 d. Logs carry no phone numbers, names or health tags." Add **FR-A9 Must**: "Privacy notice and consent screen before S2."

#### F-X-03 — Deletions and referential integrity
- Severity: Minor
- Where: §2 Admin (p.1); §8 (p.17–19)
- Quote: "add/edit/remove members"
- Fix: "Members, cooks and recipes are archived, never hard-deleted, while referenced (except under FR-A8). Archived recipes stay on existing menus with an 'Ab uplabdh nahi' tag. Tickets snapshot dish names, servings and tweaks at creation."

#### F-X-04 — Document hygiene
- Severity: Minor
- Where: Cover (p.1); §5.8 (p.11); §11 (p.22)
- Quote: "Full catalogue:" | "as on the "Design library" artboard"
- Fix: Add a header block (version, status, owner, approvers, change log), a Glossary (Hindi terms; servings, eater, due time, confirm; Fit/Tweak/No), and an appendix listing external artefacts (Kitchen staples tab, Design library, App prototype) with link and version. Rule: "Each AC is an observable test."

### Appendix A — Inputs for the technical design (Minor; belongs in the tech spec, not the FRD)

Both reviewers noted that prescribing JWT lifetimes, idempotency headers, pagination, API versioning, SLAs and RPO/RTO in the FRD bloats it and inflates the Major count. These gaps are real, so they are listed here as inputs the FRD should hand to the technical design, each Minor.

#### F-9-02 — No auth model, error format, idempotency, concurrency or versioning
- Severity: Minor (demoted from Major)
- Where: §9.1 (p.19–20)
- Quote: "The app talks to one REST backend"
- Fix (for the tech spec): "Every request is scoped to the caller's household; cross-household IDs return 404. Role checks follow the §2.1 table. Errors: `{code, message_hi, message_en, details}`. POSTs that create or transition accept an `Idempotency-Key` (double-tap on `/menus/{id}/confirm` must not create two tickets; ratings on flaky 4G must not double-submit). Ticket and menu writes carry `If-Match: version`, 409 on conflict. Cursor pagination for lists. Base path /v1, 90-day support after a new app release."

#### F-10-02 — Security, reliability and degradation NFRs are absent
- Severity: Minor (demoted from Major; the privacy-relevant retention and logging rules moved into F-X-02)
- Where: §10 (p.21–22)
- Quote: (absent — nearest text: "encrypted at rest, never sold, deletable with the")
- Fix (for the tech spec): "Availability 99.5% monthly for core APIs. Daily backups; RPO 24 h, RTO 4 h. Primary data stored in India. TLS 1.2+; tokens in Keychain/Keystore; refresh token 90 days, rotated on use. Staff access to household data via audited break-glass only. Degradation: OTP provider failover; if push fails, the in-app inbox is the source of truth."

## 6. What the FRD does well

1. **Cooking is a role, not a person (§2).** The four setups match how Indian homes run. Few products get this right.
2. **The engine decides and the AI talks (§6, §7).** "The AI never overrides a No" and "The LLM never invents recipes, ingredients or nutrition claims" are exactly the right safety boundary, and FR-O2 repeats it for substitutions.
3. **The LLM's job is limited to reading the request and writing the reply (§7.1).** JSON-only parse output, retrieval and ranking outside the LLM, a 2-sentence reply cap and a rule-based fallback. This makes the AI testable and cheap.
4. **One intent in three languages (FR-C1).** A rare, testable language requirement.
5. **Measurable latency targets (FR-C2, C3, K3, K8, O1, R1, §10).** Most FRDs say "fast".
6. **The out-of-stock ladder (§5.9).** Save the dish, then swap an ingredient, then change the dish, with approval, a timeout and an audit trail. It mirrors real kitchen behaviour.
7. **Respect for family cooks (§5.10).** Appreciation-first rating copy and the ability to turn ratings off.
8. **Duty, backup and Chef for the day (§5.7).** It plans for chhutti and illness, the everyday failure modes of home cooking; the contradictions are fixable, the concept is sound.
9. **A concrete design system (§11).** Named tokens with hex values, type, spacing and radius scales, a motion budget, reduce-motion honoured.
10. **The recipe coverage plan (§7.4).** Regional targets that add up to 1,000, weighted toward daily food.
11. **Privacy stated up front (§10).** Diet, allergy and health-like tags declared personal data. The right starting point for F-X-02.
12. **Analytics from day one (§12).** Events with properties before build, targets deferred until beta data.
13. **An honest decisions section (§13).** What was decided and deferred, with reasons, which made this review's contradictions easy to trace.
14. **A scope table with an explicit Later column (§3).**

## 7. Scope impact of this review

The FRD has 66 Musts. This report proposes both additions and demotions; the author should see the net effect rather than a longer list.

| Change | FRs | Effect |
|---|---|---|
| New Must | A7 subscription lifecycle, A8 deletion, A9 consent, K2a due time, K19 self-approval, K20 phone collision, K21 cook removal, K22 no-show escalation, P6 future-date menus, P7 eaters, P8 WhatsApp-only ticket; M6 promoted from Should | +12 |
| New Should | M8 vrat days, optional slots (Tiffin, Shaam ka nashta), offline write queue in cook mode, voice OTP fallback | 0 |
| New Could | M9 household weekday rule, F5 tweak proposals (split out) | 0 |
| Demote Must → Should | K9 recurring schedules, K15, K16, K17 Chef for the day, S4 auto-decrement, F4 weekly summary | −6 |
| **Net** | | **72 Must** |

That is still not an MVP. The additions are mostly definitions the current Musts already depend on (due time, eaters, deletion), so they do not add work so much as name it. If the count must come down, the honest cut is a feature area, not a requirement: for example, ship stock and ration (S1–S8, §5.9) as Should behind the ticket flow, which drops to about 62 Must, and keep F-5.8-01's Ingredient model so it can be added without migration. The author should pick, and then "Must blocks release" can hold.

## 8. Fix these first

1. **Add eaters, servings and guests to every menu** (F-5.6-01, F-5.5-01): a "Kaun kha raha hai?" step at confirm drives ranking, coverage, quantities and rating prompts.
2. **Define due time** (F-5.7-01): per-slot defaults, editable at confirm, used by K1, the §5.9 timeout, the no-show escalation and the on-time metric.
3. **Add the single permission and approval table, plus the self-approval rule** (F-2-02, F-2-04, F-8-01): one table, one HouseholdMembership model.
4. **Replace the ticket state table** (F-5.7-02): Unassigned as a state, Stock issue as a flag, Rated as a timestamp, a "Not confirmed" outcome that never corrupts stock or learning, and a family-cook path with no accept step.
5. **One rule for off-duty tickets** (F-5.7-06), and **one for a cook who does not turn up** (F-5.7-12).
6. **Make diet rules correct** (F-5.2-01a, F-5.2-01b, F-5.2-03, F-6-02, F-6-03): define `jain_safe` with root vegetables; add no-onion-garlic and non-veg exclusions; make allergies a Must picklist mapped to ingredient allergens; add the "katori alag" Tweak path.
7. **Split Ingredient from Staple, with scaling rules** (F-5.8-01, F-5.5-05, F-8-02).
8. **Resolve Hindi steps and TTS** (F-5.7-03): ship reviewed Hindi steps and a TTS service, or demote FR-K5.
9. **Add account and household deletion, and the consent screen** (F-5.1-03, F-X-02, F-7-02).
10. **Decide the v1 cook model** (F-2-05, F-2-06, F-5.7-10): one hired cook plus family cooks; the phone-collision rule; cook removal.
11. **Rewrite the scope sentence and settle the Must count** (F-3-01, §7 of this report, F-3-02).
12. **Fix the Tweak rules and score** (F-6-01, F-6-05, F-6-06): contra-tags; one formula with eaters, learning, repetition and stock; derived vs editorial tags.
13. **Reconcile the three stock states and give substitutions a source** (F-5.6-04, F-5.8-02, F-5.9-01).
14. **Add the notification matrix** (F-X-01, F-9-03).
15. **Remove server-sent WhatsApp and define the admin-managed WhatsApp-only ticket** (F-2-01, F-5.6-03).
16. **Add offline cook mode** (F-10-01) and **the language plan on both sides** (F-5.7-04, F-10-05, F-11-01).
17. **Settle recipe-content licensing** (F-7-06).
18. **Close the data-model, API and screen-inventory gaps** (F-8-02, F-9-01, F-4-01), and hand Appendix A to the tech spec.

## 9. Open questions for the author

1. Who decides the eaters and servings for each meal, and are guests counted by diet? (F-5.6-01)
2. What are the default due times per slot, and who can change them? (F-5.7-01)
3. Can an adult member (not the admin) approve a dish change when the admin is at work? The §2.1 table proposes yes. (F-2-02)
4. Is v1 one hired cook plus family cooks, or truly several cooks? (F-2-05)
5. Can a profile-only member (no phone) hold the cook role, and if so who taps her buttons? (F-2-03)
6. When the admin is also the cook, which approvals are skipped? (F-2-04)
7. Will recipes ship with reviewed Hindi steps, and which TTS will read them? (F-5.7-03)
8. Which regional languages come after Hindi, for cook mode and for the family UI, and in what order? (F-5.7-04, F-10-05)
9. What exactly does `jain_safe` exclude, and who signs off the Jain content policy? (F-5.2-01a)
10. Which of no-onion-garlic, pescatarian, no-beef, no-pork and halal-only are in v1? (F-5.2-01b)
11. Are vrat days and weekday veg rules v1 (Should) or Later? (F-5.2-02)
12. Is the allergen list fixed, and is allergy a Must? (F-5.2-03)
13. How many ingredients will the catalogue hold, which are tracked, and who writes the scaling rules? (F-5.8-01, F-5.5-05)
14. Do we track stock quantities or only levels, and what does S4 do without quantities? (F-5.8-02)
15. What should happen when a cook has not accepted a lunch ticket by 11:30? (F-5.7-12)
16. What happens if a cook never taps Completed: does the admin confirm, or does the ticket lapse? (F-5.7-02)
17. Can members read each other's chats, and can a hired cook use chat? (F-5.4-01)
18. What does "read-only after the trial" mean for today's tickets and the cook? (F-5.1-05)
19. Which LLM vendor, which region, and what retention and training terms? (F-7-02)
20. Are recipes "licensed" or "curated from public sources", and who signs the content policy? (F-7-06)
21. When the prototype and the FRD disagree, which wins, and where are the K-screen designs? (F-1-02)
22. Which feature area is cut or demoted to bring the Must count down? (§7)
23. What happens when a hired cook leaves, or is already registered in another household? (F-5.7-10, F-2-06)
24. Should the hired cook see member names on ratings and health reasons on tweaks? (F-5.10-01, F-5.7-05)
25. Do we need a 4th slot (shaam ka nashta) and tiffin in v1? (F-5.3-01)
26. What is the minimum Android version, based on cook-device data? (F-10-04)

## 10. Finding index

| ID | Severity | Section / FR | Page | Title |
|---|---|---|---|---|
| F-1-01 | Minor | §1 Goals | 1 | Four different "how many options" numbers |
| F-1-02 | Major | §1 Reference prototype | 1 | The prototype is "source of truth" but has no cook, stock, ration or settings screens |
| F-2-01 | Major | §2 Roles table | 1 | Admin "receives WhatsApp messages from the app", but v1 has no WhatsApp Business API |
| F-2-02 | Blocker | §2, §5.9 step 5 | 1–2, 12 | No permission matrix; "the family" is used as an actor; approval rules contradict (absorbs F-5.9-02) |
| F-2-03 | Minor | FR-A5 AC | 5 | Can a profile-only member hold the cook role? |
| F-2-04 | Major | §2 | 1–2 | Admin-as-cook collapses the approval flows |
| F-2-05 | Major | §3 scope table | 3 | "Multiple cooks" is Later, yet v1 has backup cooks, Chef for the day and reassignment |
| F-2-06 | Major | §8 User relations | 17 | The same hired cook in two households has no defined v1 behaviour |
| F-2-07 | Minor | §2 | 2 | Changing the cook setup mid-week has no rule for open tickets |
| F-2-08 | Minor | §2 setup table | 2 | "Maharaj" names both the AI and the hired cook |
| F-2-09 | Nit | §2 | 1–2 | Wording: typo, two names for one action, gendered defaults |
| F-3-01 | Major | §3 | 2 | "Everything else waits" contradicts the scope table; 66 Musts is not an MVP |
| F-3-02 | Major | §3 table | 3 | Future-date menus are needed, but no UI picks a date |
| F-3-03 | Major | §3 Pricing | 3 | Subscription lifecycle is under-specified |
| F-3-04 | Nit | §3, §8 | 3, 18 | Currency symbol; price hard-coded in the data model |
| F-4-01 | Major | §4 | 3–5 | The screen inventory omits screens the FRD relies on |
| F-4-02 | Minor | §4 S5 | 3 | The Loading screen's 3 s maximum has no timeout behaviour |
| F-4-03 | Minor | §4 K4, K6, K7 | 4–5 | Two cook screens have loose ends |
| F-4-04 | Minor | §4 Cook app screens | 4 | "Large type" for cook mode is not testable |
| F-5.1-01 | Major | FR-A1 | 5 | OTP AC untestable; resend, rate-limit and session rules missing |
| F-5.1-02 | Major | FR-A3 | 5 | The invite link logs the invitee straight in |
| F-5.1-03 | Blocker | §5.1, §10 Privacy | 5, 22 | No account or household deletion (store rejection risk) |
| F-5.1-04 | Minor | FR-A4 | 5 | Demo family lifecycle undefined |
| F-5.1-05 | Minor | FR-A6 | 5 | "Read-only after expiry" and today's tickets |
| F-5.1-06 | Minor | FR-A2 | 5 | One user, one household |
| F-5.2-01a | Blocker | FR-M2, §6.1, §6.3 | 6, 14–15 | `jain_safe` is undefined |
| F-5.2-01b | Major | FR-M2 | 6 | Four diets cannot model real Indian households |
| F-5.2-02 | Major | §5.2 | 6 | Fasting (vrat) and weekday rules are absent |
| F-5.2-03 | Blocker | FR-M6 | 6 | Allergies are a Should, free text, yet claimed as hard exclusions |
| F-5.2-04 | Major | FR-M6 | 6 | Dislikes have no engine behaviour |
| F-5.2-05 | Minor | FR-M4 | 6 | The needs list misses common Indian health needs |
| F-5.2-06 | Minor | FR-M1 | 6 | Member cap and removal |
| F-5.3-01 | Major | FR-H1 | 6 | Three fixed slots miss evening snacks and tiffin; boundaries undefined |
| F-5.3-02 | Minor | FR-H2, FR-H3 | 6 | No variety rule in the Home top-8 |
| F-5.3-03 | Minor | FR-H5–H7 | 7 | Header constraints and sticky bar scope |
| F-5.3-04 | Minor | §5.3 | 6–7 | Home ranking does not state that it avoids the LLM |
| F-5.3-05 | Minor | FR-H7 | 7 | Health constraints in the Home header are visible to anyone holding the phone |
| F-5.4-01 | Major | FR-C5, FR-C7 | 7 | Chat ownership and visibility undefined |
| F-5.4-02 | Major | FR-C3 | 7 | Latency targets have no per-stage budget |
| F-5.4-03 | Minor | FR-C5, FR-C1 | 7 | "Session" and "same intent" undefined |
| F-5.4-04 | Minor | FR-C6 | 7 | "Closest options" could surface unsafe dishes |
| F-5.5-01 | Major | FR-R3 | 8 | "Household size" undefined; no base servings |
| F-5.5-02 | Nit | FR-R2 | 8 | Fit labels differ between engine, Recipe detail and prototype |
| F-5.5-03 | Minor | FR-R5 | 8 | "Video recipe" when the source has no video |
| F-5.5-04 | Minor | FR-R4 | 8 | The "3–10 steps" AC fails for common dishes |
| F-5.5-05 | Major | FR-R3, FR-K5, FR-S3 | 8, 9, 11 | Recipe scaling is not linear |
| F-5.6-01 | Blocker | FR-K2 AC, FR-P2 | 8–9 | Nobody defines eaters, servings or guests |
| F-5.6-02 | Major | FR-P4 | 8 | One action, three names, no step to pick the assignee |
| F-5.6-03 | Major | FR-P4, §13 | 8, 24 | A WhatsApp-only cook breaks the ticket lifecycle |
| F-5.6-04 | Major | FR-P3, FR-S2, FR-S3 | 8, 11 | Three parallel stock states with no reconciliation |
| F-5.6-05 | Minor | FR-P1 | 8 | Concurrent editing of one menu |
| F-5.6-06 | Minor | FR-P5 | 8 | Bill list uses recipe units, not purchase units |
| F-5.7-01 | Blocker | FR-K2 AC | 9 | "Due time" is never defined |
| F-5.7-02 | Blocker | Ticket states table, FR-K7 | 9 | The ticket state machine has unreachable, missing and contradictory transitions (absorbs F-5.7-07) |
| F-5.7-03 | Blocker | FR-K5, §13 | 9, 25 | Hindi audio is a Must while Hindi steps are an open question; no TTS |
| F-5.7-04 | Major | §2, §4, §8, §10 | 2, 4, 18, 22 | "Hindi-first" cook mode assumes a North Indian cook |
| F-5.7-05 | Major | FR-K1, FR-K4 | 9 | The hired cook sees health-like data through tweaks |
| F-5.7-06 | Blocker | FR-K10, K11, K14 | 10 | Off duty: three Musts, three answers |
| F-5.7-08 | Minor | FR-K3 | 9 | Push delivery time; "what changed" undefined |
| F-5.7-09 | Minor | FR-K15–K17 | 11 | Chef for the day: permissions, arbitration and midnight |
| F-5.7-10 | Major | FR-K1 | 9 | No off-boarding for a hired cook |
| F-5.7-11 | Minor | FR-K12 | 10 | "If nobody else can cook" has no trigger |
| F-5.7-12 | Major | FR-K8, K10–K12 | 10 | A hired cook who does not turn up has no escalation |
| F-5.8-01 | Blocker | §5.8 intro, FR-S3, §8 | 11, 18 | A 110-item staple catalogue cannot back 1,000 recipes |
| F-5.8-02 | Major | FR-S2, FR-S4 | 11 | Stock decrement has no quantities or thresholds |
| F-5.8-03 | Minor | FR-S1 | 11 | Catalogue edits: permission, custom items, deletion |
| F-5.8-04 | Minor | §2, FR-S6, FR-S7 | 2, 12 | Family cook ration approval; no partial purchase |
| F-5.9-01 | Major | §5.9 steps 2–3 | 12 | Substitutions need a source |
| F-5.9-03 | Minor | §5.9 step 6 | 12 | The timeout clause is ambiguous |
| F-5.9-04 | Minor | FR-O1 | 12 | 5 s suggestions against an 8 s LLM timeout |
| F-5.9-05 | Minor | §5.9 step 1 | 12 | The creation-time stock check is unspecified |
| F-5.9-06 | Minor | §5.9 step 2 | 12 | "Same dish, different recipe" needs unplanned content |
| F-5.10-01 | Major | FR-F3 | 13 | Named ratings shown to the hired cook |
| F-5.10-02 | Major | FR-F5 | 13 | Learning rules not specified enough to build or test |
| F-5.10-03 | Minor | FR-F6 | 13 | The 3-day no-repeat rule fights everyday food |
| F-5.10-04 | Minor | FR-F1, FR-F2 | 13–14 | Rating prompts, proxy ratings and opting out |
| F-6-01 | Major | §6.1 | 14 | "Recipe not tagged" rules make almost everything a Tweak |
| F-6-02 | Major | FR-K4, §6.1 | 9, 14 | The K4 example is a Tweak the engine can never produce |
| F-6-03 | Minor | §6.1 | 14 | The Veg rule omits fish; rule order gives wrong reasons |
| F-6-04 | Nit | §6.1 Spice rows | 14 | Spice matrix only implicit |
| F-6-05 | Major | §6.2 | 15 | The score ignores eaters, learning, repetition and stock |
| F-6-06 | Major | §6.3 | 15 | Tag set missing safety and India-specific tags; undefined ones |
| F-6-07 | Minor | §8 FitCache, §6.2 | 19, 15 | FitCache invalidation and badge arithmetic |
| F-7-01 | Major | §7.1 step 2 | 15 | Hard vs soft filters undefined |
| F-7-02 | Major | §7.1 step 1 | 15 | Personal data to a third-party LLM with no data-handling terms |
| F-7-03 | Major | §7 | 15–16 | No cost cap, rate limit or prompt-injection handling |
| F-7-04 | Minor | §7.1 step 4 | 15 | The Write step has no guard or fallback |
| F-7-05 | Minor | §7.2 | 16 | Intent mappings that will surprise users |
| F-7-06 | Major | §7.4, §13 | 16, 24–25 | Recipe licensing is contradictory |
| F-7-07 | Minor | §7.3 | 16 | Reply language vs the user's language setting |
| F-7-08 | Minor | §7.4 coverage | 17 | No minimum counts for restricted diets |
| F-8-01 | Major | §8 User | 17 | A single `User.role` cannot represent the FRD's roles |
| F-8-02 | Major | §8 | 17–19 | Entities and fields required by FRs are missing (absorbs F-8-03) |
| F-9-01 | Major | §9.1 | 19–20 | Endpoints are missing for existing FRs |
| F-9-02 | Minor | §9.1 | 19–20 | Auth, errors, idempotency, concurrency, versioning (Appendix A) |
| F-9-03 | Minor | §9.2 | 21 | External services table gaps |
| F-10-01 | Major | §10 Offline | 21 | Cook mode has no offline behaviour |
| F-10-02 | Minor | §10 | 21–22 | Security, reliability and degradation NFRs (Appendix A) |
| F-10-03 | Minor | §10 Accessibility | 22 | Accessibility omits text scaling and older users |
| F-10-04 | Minor | §10 Performance, Platforms | 21–22 | Performance targets lack conditions; Android floor |
| F-10-05 | Major | §10 Language, §7.3 | 22, 16 | Regional languages on the family side; Hinglish default |
| F-11-01 | Major | §11.2 | 23 | The chosen typefaces have no Devanagari |
| F-11-02 | Nit | §11 | 22–23 | Token hygiene and motion cost |
| F-12-01 | Minor | §12 | 23–24 | Events needed to run the product are missing |
| F-12-02 | Minor | §9.2, §12 | 21, 23–24 | Analytics privacy covers names, not properties; metric wording |
| F-13-01 | Minor | §13 | 24–25 | Decisions contradict the body; open-questions list too short |
| F-13-02 | Minor | §13 Decisions | 25 | "Voice-only cook mode not needed" is an untested assumption |
| F-X-01 | Major | §9.2 Push, FR-K3 etc. | 21 | No notification matrix |
| F-X-02 | Major | §10 Privacy | 22 | DPDP Act 2023 obligations are not addressed |
| F-X-03 | Minor | §2, §8 | 1, 17–19 | Deletions and referential integrity |
| F-X-04 | Minor | Cover | 1 | Document hygiene |

---

## 3. What the team accomplished

- **Planner** set 13 evaluation criteria and a seed list of sections and FR-IDs; the Builder's independent read corrected the plan's own FR count (74, not 78) and found real bugs the seed list did not predict (the unproducible K4 Jain example, "15 min" → `max_minutes: 20`, Fit/Tweak/No vs Perfect/Tweak/Nahi).
- **Builder** produced a 108-finding report with paste-ready requirement text, all 245 quotes machine-verified verbatim against the FRD.
- **Sonnet reviewer** independently re-ran the quote check and structural counts, and caught the FR-ID transparency gap (every FR-xx label is reconstructed, since the ID column did not survive extraction).
- **Opus reviewer** read the whole FRD and found the substantive weaknesses: an unapplied severity rubric, two contradictory paste-ready tables, two flaws in the replacement state machine, a scope self-contradiction, a probable misread, and four missed findings (cook no-show, non-linear scaling, family-side regional languages, header health labels).
- **Synthesizer** rewrote the rubric and re-graded to 10 Blockers, merged and split findings to 111, reconciled the permission and approval tables into one, fixed the state table, added a net-Must-count section, moved tech-spec detail to an appendix, rejected the one reviewer claim that was itself wrong (the line count), and re-verified the final file: 254/254 quotes verbatim, body and index severities in agreement.