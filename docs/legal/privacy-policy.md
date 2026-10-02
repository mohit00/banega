# Banega Privacy Policy

> **DRAFT — must be reviewed by a qualified Indian lawyer before publishing.**
> Placeholders are in `[SQUARE BRACKETS]`. Notes for the reviewer are in `[Note: …]` and must be removed before publishing.

- Version: 2026-09

`[Note: matches the in-app consent version CONSENT_VERSION = "2026-09" (backend) and kConsentVersion (app). Bump both when this policy changes materially.]`

- Effective date: `[EFFECTIVE DATE]`
- Public URL: https://banega.kornea.in/privacy

> **Short mein (Hinglish summary)**
> Banega aapke ghar ka khaana plan karne ke liye aapka phone number, family ki pasand, allergy, vrat ke din aur khaane ka itihaas rakhta hai. Data kabhi becha nahi jaata. Maharaj chat ka sawaal ek AI service (Anthropic Claude) ko jaata hai — phone number aur health needs kabhi nahi; family ka naam sirf tab jab aapne khud likha ho. Settings se data export kar sakte ho, aur account ya poora ghar delete kar sakte ho (7 din tak undo, phir hamesha ke liye mit jaata hai). Shikayat ke liye: `[GRIEVANCE OFFICER EMAIL]`.

---

## 1. Who we are

Banega is a household meal-planning app made by **`[KORNEA LEGAL ENTITY NAME]`** ("Kornea", "we", "us"), `[REGISTERED ADDRESS]`, `[CIN / registration number]`.

For the purposes of the Digital Personal Data Protection Act, 2023 ("DPDP Act") and the Digital Personal Data Protection Rules, 2025, Kornea is the **Data Fiduciary** for the personal data processed through Banega. You are the **Data Principal**.

Contact: **anshul@kornea.in**

## 2. Who this policy covers

Banega is used by a household. One person creates the household and becomes its **admin**. The admin can add:

- **Family members** — as food profiles (a name and food preferences), with or without their own login.
- **Children** — as food profiles only; children do not get their own login (see section 7).
- **Cooks** — a family member who cooks, or a hired cook added by phone number. A hired cook may log in with their own phone, or the admin can operate cook mode on the admin's phone.

This policy covers everyone whose data is in Banega: the admin, family members, children's profiles and cooks.

`[Note: the admin enters data about other people (family, children, the cook). The Terms of Service make the admin responsible for having the right to do so and for telling those people. The reviewer should confirm this is adequate under DPDP section 6 / the consent requirement, or whether each adult member and the hired cook need their own notice at first login. Today every user who logs in sees the consent screen; profile-only members and a cook operated "via admin" never do.]`

## 3. What personal data we collect

| Category | What exactly | Where it comes from |
|---|---|---|
| Account and login | Mobile phone number; your name (optional); app language; a device identifier the app generates; login sessions | You, at sign-up |
| One-time passwords | Phone number, a hashed (not readable) OTP code, device identifier, attempt count | Created when you request an OTP |
| Household | Household name, time zone, meal times, default servings, settings | The admin |
| Family member profiles | Name, colour, whether the profile is a child, diet (veg, Jain, no onion-garlic, eggetarian, pescatarian, non-veg, with meat exclusions), dairy-free, spice level, cuisines, dislikes, **allergies** (picklist plus free text), **food needs** (e.g. low sugar, low oil, high protein, kid-friendly, no maida), **fasting (vrat) weekdays**, whether needs show on Home | The admin, or the member |
| Cook details | Cook name, kind (hired or family), **hired cook's phone number**, on-duty / off-duty status and reason, duty history, primary / backup role | The admin, or the cook |
| Meal planning and kitchen | Menus, who is eating, guest counts, notes, tickets sent to the cook and their status history, messages on tickets, stock levels, ration (shopping) requests and approvals | Household members and the cook |
| Ratings and history | Dish ratings (bura / theek / bahut accha) per member, optional rating notes, what was cooked when | Household members |
| Maharaj chat | Your questions and Maharaj's replies, the filters understood, the suggested recipes | You |
| Notifications | Push notification token, platform, app version, notification preferences and quiet hours, in-app inbox items | Your device and you |
| Subscription | Store (Google Play), product, trial and renewal dates, status, Google Play purchase token; for the free trial, the phone number and device identifier that used the trial | Google Play and the app |
| Consent | Which notice version you accepted, and when | You |
| Data exports | The export file you requested, and who requested it | The admin |
| Technical | IP address in server access logs and for abuse limits on OTP requests; crash reports if enabled (section 9) | Your device |

We do **not** collect: email address, postal address, precise location, contacts, photos, camera or microphone recordings, payment card details (Google Play handles payment), or government IDs. The Android app asks only for internet access; it does not request microphone, camera, location or contacts permissions. Recipe steps can be read aloud using your phone's own text-to-speech.

`[Note: verified against android/app/src/main/AndroidManifest.xml (INTERNET only) at drafting. If a microphone permission is added for voice chat, add "voice input" and the speech provider here and in the Data safety form.]`

## 4. Why we use it (purposes)

We use personal data only for these purposes:

1. **Log you in and keep your account secure** — phone number, OTP, device identifier, sessions, IP-based abuse limits.
2. **Plan meals that suit everyone** — diets, allergies, needs, vrat days, dislikes, spice and cuisines decide which recipes are shown and which are ruled out.
3. **Run the kitchen with your cook** — send menus as tickets to the cook, track ticket status, stock and ration requests, duty and backup cover.
4. **Maharaj chat suggestions** — understand your question and write a short reply (section 8).
5. **Learn from ratings** — improve suggestions for your household.
6. **Notifications** — tickets, reminders, approvals, trial and weekly summaries, according to your preferences.
7. **Subscription and trial** — check your plan with Google Play, and stop the free trial being used more than once per phone and device.
8. **Your rights** — export, deletion and grievance handling.
9. **Keep the service working** — fix crashes and errors, prevent abuse, keep backups.
10. **Legal compliance** — respond to lawful requests and meet legal obligations.

We do **not** sell personal data, use it for advertising, or build profiles for anyone outside your household.

## 5. Legal basis

- **Consent (DPDP section 6).** Before you use Banega, the app shows a notice and asks you to agree. We record the version and the time. You can read the notice again in **Settings → Privacy & data → Review consent**. You can withdraw consent at any time by deleting your account (section 11). Withdrawing does not affect processing that already happened.
- **Legitimate uses (DPDP section 7)** where they apply, for example: data you voluntarily give us for a specified purpose where you have not said you do not consent, compliance with law or a court order, and responding to a medical emergency or threat to safety.

`[Note: the reviewer should decide which purposes rest on consent and which on section 7, and whether a separate, specific consent is needed for the AI processing (purpose 4). Today one "I agree" covers all purposes; the consent screen describes the AI processing separately.]`

## 6. Allergies, food needs and fasting days

The DPDP Act does not define a separate "sensitive" class, but we treat this data with extra care because it can reveal health or religious practice:

- Allergies, food needs (e.g. low sugar), Jain or no-onion-garlic diet and vrat days are used **only** to decide which recipes are suitable.
- Health-like needs are shown on the Home screen only for members who chose to show them.
- A hired cook sees ratings **without names** unless the admin turns names on.
- These details are **never** sent to the AI service by name (section 8), and never written to crash reports.
- **Allergy information in Banega is a guide only.** Always check the labels of packaged ingredients. Banega is not medical or nutrition advice (see the Terms of Service).

## 7. Children

- A child in Banega is a **food profile** (a name and food preferences) added by the household admin. Children do not log in.
- When adding a child, the admin confirms on the consent screen that they are adding the profile **as the child's parent or lawful guardian** ("You add kids' profiles as their parent or guardian").
- We use a child's profile only to plan the household's meals. We do not track children's behaviour, show them advertising, or target them in any way (DPDP section 9(3)).
- We do not knowingly let anyone under 18 create their own Banega login. If you believe a child has done so, write to us and we will delete the account.

`[Note — verifiable parental consent: DPDP section 9(1) and the 2025 Rules require "verifiable consent" of the parent before processing a child's data. Today the position is: (a) the admin is an adult who logged in with an OTP-verified phone; (b) the admin declares on the consent screen that they act as parent or guardian; (c) the child has no account and the data is minimal and household-internal. The reviewer must confirm whether this is sufficient, or whether the Rules' verification methods (e.g. reliable identity/age details already held, or a virtual token) are needed. There is no in-app age check today; invited members with their own login are assumed to be adults. Decide whether to add an "I am 18 or older" confirmation.]`

## 8. Maharaj (AI chat) and what the AI service receives

Maharaj uses **Anthropic's Claude API** to understand your question and to word the reply. Recipe matching and every allergy and diet rule are done by Banega's own engine, not by the AI.

When you ask Maharaj a question, we send Anthropic:

- **the text you typed** (as you typed it);
- the meal (breakfast / lunch / dinner), the dish names Banega already chose, and the filters it understood or relaxed;
- a **family constraints summary** where:
  - allergies appear **only as counts** (e.g. "one peanut allergy") — never with a name;
  - diet or mild-spice needs (Jain, no onion-garlic, mild spice for a child) are named **only for a family member whose name you typed in that question**; everyone else is counted (e.g. "two other Jain eaters");
- the names of family members **only if you typed them** in the question.

We **never** send: phone numbers, food needs such as low sugar, vrat days, the household name, the names of members you did not type, your earlier chat messages, or your account identifiers.

If you type something personal in a question (for example a name or a medical condition), that text is sent as you wrote it. Please do not type information you do not want processed.

If the AI service is slow or unavailable, Banega answers using its own rules and a template reply, and nothing is sent.

`[Note: Anthropic's API terms state that API inputs and outputs are not used to train models by default and are retained for a limited period for trust and safety. Confirm the current retention period and whether zero-data-retention applies to our account before publishing, and state it here (see ai-and-vendor-terms.md). A short-lived cache (24 hours) of the understood filters — not your words in readable form, keyed by a hash — is kept on our own server.]`

## 9. Service providers (processors) and who receives what

We use these service providers to run Banega. They process data on our instructions under contract and may not use it for their own purposes.

| Provider | Purpose | What it receives | Location |
|---|---|---|---|
| `[CLOUD HOST — e.g. provider and region]` | Hosts our servers, database, cache and backups | All data described in section 3 (encrypted in transit) | `[India / region]` |
| MSG91 (Walkover Web Solutions Pvt Ltd) `[confirm]` | Sends OTP by SMS (voice fallback) | Your phone number and the OTP message | India |
| Google — Firebase Cloud Messaging | Delivers push notifications | Push token, and the notification title and text (which can include dish names, a cook or member name, and ticket status) | `[Global — Google]` |
| Google Play (Billing) | Subscription purchase, renewal and refunds | Google Play handles your payment directly under Google's own terms; we receive the purchase token and subscription status | Global |
| Anthropic, PBC — Claude API | Maharaj chat understanding and reply wording | Only what section 8 lists | United States |
| Sentry (Functional Software, Inc.) — **only if enabled** `[confirm]` | Crash and error reports | Error details, app version, device model and an opaque user ID. Phone numbers, tokens, OTP codes, request bodies, IP addresses and names are removed before sending | `[US / EU — choose]` |

`[Note: Voyage AI embeddings exist in the code as an optional setting for recipe search and are switched off. If enabled, confirm whether only recipe text (no user data) is sent and add it here.]`

We may also disclose personal data if required by law, a court order or a government authority, or to protect the safety of a person.

## 10. Transfers outside India

Some providers (Anthropic, Google, and Sentry if enabled) may process data outside India, mainly in the United States. The DPDP Act allows transfers except to countries the Central Government restricts by notification. We will stop or change any transfer that becomes restricted. We minimise what leaves India: for example, the AI service never receives phone numbers or health needs.

## 11. How long we keep data

These periods come from Banega's automatic clean-up jobs.

| Data | How long |
|---|---|
| OTP codes | Expire after 5 minutes; OTP request records are deleted after 1 day |
| Login sessions | Until they expire, or 7 days after you log out |
| Maharaj chat | Deleted 30 days after the conversation was last used |
| Inbox items | 90 days |
| Push notification records (sent or failed) | 7 days |
| Data export files | Deleted 7 days after they are ready |
| Household data (members, cooks, menus, tickets, ratings, cooked history, stock, ration, subscription record) | While the household exists |
| Deleted household | 7-day undo window, then permanently deleted |
| Deleted account | 7-day undo window, then your phone number and name are erased, and your devices, sessions, private chats, consent records and inbox are deleted |
| Server access logs (IP address, time, address requested) | `[X days — set by hosting log retention]` |
| Crash reports (if enabled) | `[X days — Sentry retention setting]` |
| Backups | `[X days — backups containing deleted data are overwritten within this period; FRD target ≤ 30 days]` |

`[Note — gaps found in the code that the reviewer and developer should decide on:
1. Ratings and cooked history have no time limit while the household exists (the FRD suggested 2 years).
2. When a user deletes their account, things they contributed to the household — their food profile, ticket messages, ratings — stay with the household (the household's record), linked to an erased user. The policy says so in section 12; confirm this is acceptable.
3. When a hired cook is removed or deletes their account, the archived cook record keeps the cook's name and phone number until the household is deleted. Consider blanking the phone on removal.
4. Notification preferences are not deleted when an account is purged.
5. The admin-panel audit log (staff actions, with before/after snapshots that can contain personal data) has no retention limit.
6. Backup retention and purge are not in the code yet.]`

## 12. Your rights and how to use them

Under the DPDP Act you have the right to:

| Right | How to use it in Banega |
|---|---|
| **Access** — a summary of your data and processing | The household admin can use **Settings → Privacy & data → Export my data**. A download link arrives in the inbox; it stays valid for 7 days. The export includes your own Maharaj chats only — other members' chats are private to them. Other members can ask the admin or write to us. |
| **Correction and completion** | Edit profiles, preferences and household settings in the app at any time. |
| **Erasure** | **Settings → Delete my account** removes your login (you can undo within 7 days by logging in again). The admin can use **Settings → Delete household** to erase all household data after a 7-day undo window. The only admin must make someone else admin, or delete the household, first. You can also email us. |
| **Withdraw consent** | Delete your account, or write to us. |
| **Grievance redressal** | Write to the Grievance Officer (section 13). |
| **Nomination** | You can nominate a person to exercise your rights if you die or become incapable. Write to us with the nominee's name and contact. |

Deleting your account or household in Banega **does not cancel your Google Play subscription**. Cancel it in Google Play → Payments & subscriptions.

What stays after you delete your account: the household keeps the shared records you took part in (your food profile, menus, tickets, ticket messages and ratings), without your phone number or name on your login. If you want those removed too, ask the admin to delete your profile, or write to us.

### Delete your account or data without the app {#delete-account}

If you cannot use the app, email `[GRIEVANCE OFFICER EMAIL]` with the subject "Delete my Banega account" and your registered phone number. Say whether you want your own account deleted, or (if you are the admin) the whole household. We will verify the request with an OTP to that number or another reasonable check, then delete as described above — usually within `[7]` days of verification. Remember to cancel your Google Play subscription separately.

`[Note: export is admin-only today (POST /v1/export requires the edit-household permission). Non-admin members cannot self-serve an access request. Either add a per-user export or keep the email route above and respond within the time limit the Rules set.]`

## 13. Grievance Officer

If you have a concern about your personal data, contact:

**`[GRIEVANCE OFFICER NAME]`**, Grievance Officer, `[KORNEA LEGAL ENTITY NAME]`
Email: `[GRIEVANCE OFFICER EMAIL]` · Address: `[REGISTERED ADDRESS]`

We will acknowledge your grievance and respond within `[the period prescribed under the DPDP Rules — confirm, e.g. 90 days]`.

`[Note: the app's Settings currently shows "Grievance contact: privacy@banega.app". The email here, the app string (key settingsGrievance in three ARB files) and the Play listing must all match. Confirm the address exists.]`

## 14. Data Protection Board of India

If you are not satisfied with our response to your grievance, you may complain to the **Data Protection Board of India** under the DPDP Act, after first using our grievance process.

## 15. How we protect data

- All app-to-server traffic uses HTTPS (TLS).
- OTP codes and invite codes are stored only as hashes; login uses short-lived access tokens and a rotating refresh token tied to each device.
- Every request is limited to the caller's own household; Maharaj chats are private to the person who wrote them, even from the admin.
- Rate limits on OTP and Maharaj protect against abuse.
- Crash reports, if enabled, are scrubbed of phone numbers, tokens, codes, request bodies, names and IP addresses before they leave the device or server.
- Our staff admin panel requires email, password and a one-time authenticator code, and every staff change is recorded in an audit log.
- `[Encryption at rest of the database and backups — confirm with the hosting set-up.]`

If a personal data breach happens, we will inform the Data Protection Board and affected users as the DPDP Act and Rules require.

`[Note: a written breach-response procedure is needed (FRD F-X-02). Not yet in the repository.]`

## 16. Cookies and tracking

The Banega app does **not** use cookies, advertising IDs, or third-party analytics or advertising SDKs. Our website pages for this policy and the Terms do not set cookies.

## 17. Changes to this policy

We will update the version and effective date at the top when we change this policy. If a change affects what we collect, why, or who receives it, the app will ask you to read and accept the new notice before you continue.

## 18. Contact

`[KORNEA LEGAL ENTITY NAME]` · `[REGISTERED ADDRESS]` · **anshul@kornea.in**
