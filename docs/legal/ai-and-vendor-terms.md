# Banega AI and Vendor Terms Checklist

> **DRAFT — must be reviewed by a qualified Indian lawyer before publishing.**
> Internal checklist: what to verify, accept or sign with each vendor before launch. Links are to the vendors' public pages as known at drafting time; vendors move pages, so confirm each link and save a dated PDF copy of what you accepted.

> **Short mein (Hinglish summary)**
> Har vendor ke saath launch se pehle: unki terms padho, DPA (data processing agreement) accept/sign karo, data kahan rakha jaata hai aur kitne din — likh ke rakho. Anthropic: API data par training nahi, retention confirm karo. MSG91: DLT registration aur SMS template approval zaroori. Google Play: Data safety form aur account deletion link. Firebase, hosting, Sentry: DPA.

---

## How to use this checklist

For each vendor: tick each box, record the date, the plan/tier, the region chosen, and where the signed or accepted copy is stored. Update `privacy-policy.md` section 9 (processors table) and section 11 (retention) with the confirmed facts, then regenerate `site/privacy.html`.

| Vendor | Status | Owner | Date | Copy stored at |
|---|---|---|---|---|
| Anthropic (Claude API) | ☐ | `[ ]` | `[ ]` | `[ ]` |
| MSG91 (OTP SMS) | ☐ | `[ ]` | `[ ]` | `[ ]` |
| Google Play (Billing, Console) | ☐ | `[ ]` | `[ ]` | `[ ]` |
| Firebase Cloud Messaging | ☐ | `[ ]` | `[ ]` | `[ ]` |
| Cloud host `[name]` | ☐ | `[ ]` | `[ ]` | `[ ]` |
| Sentry (if enabled) | ☐ | `[ ]` | `[ ]` | `[ ]` |
| Voyage AI (only if embeddings are enabled) | ☐ | `[ ]` | `[ ]` | `[ ]` |
| Apple App Store (only if iOS launches) | ☐ | `[ ]` | `[ ]` | `[ ]` |

---

## 1. Anthropic — Claude API (Maharaj)

What Banega sends (verified in `backend/app/services/maharaj/parse.py` and `write.py`): the user's typed question; meal slot; dish names already chosen; filters understood/relaxed; family constraints with allergies as counts and diet/spice named only for members whose name the user typed. Never phone numbers, health needs, vrat days, household name or chat history. Models are set by `MAHARAJ_PARSE_MODEL` / `MAHARAJ_WRITE_MODEL`.

- [ ] Account is on Anthropic's **commercial** API terms (not consumer terms). — https://www.anthropic.com/legal/commercial-terms
- [ ] **No training on API data**: confirm the commercial terms state that customer inputs/outputs are not used to train models (default for the API). Record the clause.
- [ ] **Retention**: confirm the current default retention period for API inputs/outputs and the trust-and-safety exception. Decide whether to request **zero data retention** (needs an agreement with Anthropic). Put the confirmed period in privacy-policy section 8. — https://privacy.anthropic.com (Privacy Center) and https://www.anthropic.com/legal/privacy
- [ ] **DPA**: accept Anthropic's Data Processing Addendum (it is incorporated into the commercial terms; confirm the current version). — https://www.anthropic.com/legal/data-processing-addendum `[verify link]`
- [ ] **Region / transfer**: data is processed in the United States `[confirm; check whether a regional/data-residency option exists for our account]`. Covered by privacy-policy section 10.
- [ ] **Usage policy**: Maharaj (cooking suggestions) is within the acceptable use policy; health wording is restricted by our post-validator (no cure / diabetes-safe / weight-loss claims). — https://www.anthropic.com/legal/aup
- [ ] **Sub-processors**: save Anthropic's sub-processor list. — https://www.anthropic.com/legal/subprocessors `[verify link]`
- [ ] Set a monthly spend limit in the Console that matches the per-household daily budget (`MAHARAJ_DAILY_BUDGET`).
- [ ] Engineering: before launch, run the FRD F-7-02 acceptance check — audit a sample of 1,000 logged LLM requests for phone numbers and untyped names.

## 2. MSG91 — OTP by SMS (and voice fallback)

The other agent is wiring MSG91 in `backend/app/services/otp.py` (`OTP_PROVIDER=msg91`). MSG91 receives the phone number and the OTP message.

- [ ] Sign MSG91's terms and privacy policy; ask for their **DPA** or data-processing clause and data location (India). — https://msg91.com/terms-of-use , https://msg91.com/privacy-policy `[verify links]`
- [ ] **TRAI TCCCPR 2018 / DLT** registration (mandatory for commercial SMS in India):
  - [ ] Register Kornea as a **Principal Entity** on an operator DLT portal (e.g. Jio, Airtel, Vodafone Idea "Vilpower", BSNL) and get the PE ID. — https://trueconnect.jio.com , https://www.vilpower.in `[verify]`
  - [ ] Register a **sender ID / header** (6 characters, e.g. `BANEGA`) under the *transactional / service-implicit* category.
  - [ ] Register the **OTP content template(s)** in each language used (English / Hinglish / Hindi), with the variable for the code. Template text must match exactly what the backend sends.
  - [ ] Link PE ID, header and template IDs in the MSG91 dashboard; set the DLT template ID in the backend config.
  - [ ] If using MSG91's voice OTP fallback, confirm whether separate registration is needed.
- [ ] Keep MSG91's delivery logs retention in mind (phone numbers); ask how long they keep them and record it in privacy-policy section 11.
- [ ] Check TRAI's latest directions on URL/callback whitelisting in SMS (the OTP message should carry no links). — https://www.trai.gov.in

## 3. Google Play — distribution, Billing, Data safety

- [ ] Accept the **Developer Distribution Agreement** for the Kornea developer account (organisation account, D-U-N-S if required). — https://play.google.com/about/developer-distribution-agreement.html
- [ ] **Payments policy**: digital subscription sold only via Google Play Billing. — https://support.google.com/googleplay/android-developer/answer/9858738
- [ ] **Subscriptions policy**: paywall shows price, billing period (weekly), that it auto-renews, how to cancel, and the trial length clearly. — https://support.google.com/googleplay/android-developer/answer/140504 `[verify link]`
- [ ] **User Data policy**: privacy policy link in the Console and inside the app (done: Settings → Privacy policy, consent screen). — https://support.google.com/googleplay/android-developer/answer/10144311
- [ ] **Data safety form**: fill using `play-data-safety.md`. — https://support.google.com/googleplay/android-developer/answer/10787469
- [ ] **Account deletion requirement**: in-app deletion (done) **and** a web link where users can request deletion without the app. — https://support.google.com/googleplay/android-developer/answer/13327111
- [ ] **Real-time developer notifications** (Pub/Sub) set up for subscription status (the backend has the RTDN webhook).
- [ ] Merchant profile, GST details and tax settings for India.
- [ ] Refund approach recorded (Play handles refunds; link in Terms §6). — https://support.google.com/googleplay/answer/2479637
- [ ] Content rating questionnaire (IARC) — answers in `play-data-safety.md`.

## 4. Firebase Cloud Messaging (push)

Firebase receives the push token and the notification title/body (can include dish names, a member or cook name, ticket status). Push is wired as a stub today (`PUSH_PROVIDER=fcm`, `backend/app/services/notifications.py`).

- [ ] Accept the **Firebase Data Processing and Security Terms** in the Firebase console (Project settings → Privacy). — https://firebase.google.com/terms/data-processing-terms
- [ ] Read Firebase privacy and security information; note that FCM is a global service. — https://firebase.google.com/support/privacy
- [ ] Do not enable Google Analytics for Firebase or Crashlytics unless the privacy policy and Data safety form are updated (the app uses neither today).
- [ ] Consider keeping push text generic for sensitive events (no allergy or health words in notifications).

## 5. Cloud host `[name — to be chosen]`

Hosts the API, Postgres, Redis, worker, nginx, export files (`MEDIA_DIR/exports`) and backups (`infra/docker-compose.prod.yml`).

- [ ] Choose a provider and **region** (India region recommended, e.g. Mumbai/Hyderabad, to minimise cross-border transfer).
- [ ] Accept/sign the provider's **DPA**; save the sub-processor list.
- [ ] Confirm **encryption at rest** for disks, database and backups; record it in privacy-policy section 15.
- [ ] Decide **backup retention** (FRD target: deleted households purged from backups within 30 days; build-plan RPO 24 h / RTO 4 h). Record it in privacy-policy section 11.
- [ ] Decide **log retention** for nginx access logs (they contain IP addresses) and application logs. Record it in privacy-policy section 11.
- [ ] Note CERT-In directions (April 2022): incident reporting within 6 hours and log retention for 180 days for certain entities — confirm with the lawyer whether they apply and reconcile with the log retention above. — https://www.cert-in.org.in

## 6. Sentry (crash reporting) — only if `SENTRY_DSN` is set

Scrubbing is in `backend/app/core/sentry.py` and `app/lib/core/crash_reporting.dart` (phone numbers, tokens, OTP/invite codes, URL secrets, request bodies, headers, IP and names removed; user reduced to an opaque id; no screenshots).

- [ ] Accept Sentry's **DPA**. — https://sentry.io/legal/dpa/
- [ ] Choose the data region (US or EU) and record it. — https://sentry.io/privacy/
- [ ] Set event retention and turn off IP address storage in project settings ("Prevent storing of IP addresses").
- [ ] If Sentry is not enabled at launch, remove its row from the privacy policy or keep the "only if enabled" wording.

## 7. Voyage AI — only if embeddings are enabled

`VOYAGE_API_KEY` / `EMBEDDING_MODEL` exist in config but the provider is not wired (`backend/app/services/maharaj/retrieve.py`).

- [ ] Before enabling: confirm whether only recipe text is embedded, or user queries too. If user text is sent, add Voyage to the privacy policy processors table and the consent notice, and sign its terms/DPA. — https://www.voyageai.com/privacy `[verify link]`

## 8. Apple App Store — only if iOS launches

- [ ] Apple Developer Program License Agreement; App Privacy "nutrition labels"; in-app account deletion (done, Guideline 5.1.1(v)); subscriptions via StoreKit. — https://developer.apple.com/app-store/review/guidelines/
