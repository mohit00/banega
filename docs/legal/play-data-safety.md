# Banega Google Play Data Safety and Content Rating Answers

> **DRAFT — must be reviewed by a qualified Indian lawyer before publishing.**
> Ready answers for Play Console → App content. Based on the code at drafting time (Android permissions: INTERNET only; no ads or analytics SDKs; Sentry only if `SENTRY_DSN` is compiled in). Re-check before every release that adds an SDK, permission or data field.

> **Short mein (Hinglish summary)**
> Play Console ke "Data safety" form ke jawab yahan hain: hum kaun sa data lete hain (phone, naam, health jaisi info, messages, purchase, device ID), kis kaam ke liye, aur ki ye data kisi ko "share" nahi hota (vendors sirf hamari taraf se kaam karte hain). Sab data HTTPS se jaata hai, aur user app ke andar aur web link se delete maang sakta hai. Content rating: sabke liye (Everyone / 3+).

---

## 1. Data safety — overview questions

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS/TLS to our API; vendors use HTTPS). `[Confirm production uses TLS only — infra/nginx/tls.conf.example]` |
| Which of the following methods of account creation does your app support? | **Phone number + OTP** (no username/password, no OAuth) |
| Do you provide a way for users to request that their data be deleted? | **Yes** — in-app (Settings → Delete my account / Delete household) and a web link |
| Delete account URL (required) | **https://banega.kornea.in/privacy#delete-account** |
| Does your app allow users to delete some data without deleting the account? | **Yes** — users can edit or remove member profiles, cooks, menus and stock; chats auto-delete after 30 days |
| Independent security review (MASA) | **No** (optional) |
| Is your app's target age group including children? (Target audience, separate section) | **No** — target audience 18+. Children appear only as profiles a parent adds. |

## 2. Data types — collected

"Shared" = **No** for every row: our providers (cloud host, MSG91, Firebase, Google Play, Anthropic, Sentry) act as **service providers** processing data on our behalf, which Google's definition excludes from "sharing". `[Reviewer: confirm Anthropic is engaged as a processor under its commercial terms/DPA; if not, Messages and Health info must be marked "Shared".]`

"Processed ephemerally" = **No** unless stated. "Required or optional": as below.

| Category → Data type | Collected | Optional? | Purposes (Play's list) | Notes |
|---|---|---|---|---|
| Personal info → **Name** | Yes | Optional (user name); member names are needed to use the app | App functionality, Account management | User display name; family member and cook names |
| Personal info → **Phone number** | Yes | Required | App functionality, Account management, Fraud prevention, security & compliance | Login OTP; hired cook's phone; one trial per phone |
| Personal info → **Other info** | Yes | Required | App functionality, Personalization | Diet, dislikes, spice, cuisines, child flag |
| Personal info → **Religious or political beliefs** | Yes `[decision]` | Optional | App functionality, Personalization | Jain diet and vrat (fasting) days can reveal religious practice. Conservative answer: declare it. `[Reviewer decides; if "No", remove.]` |
| Personal info → Email, Address, User IDs, Race/ethnicity, Sexual orientation | No | — | — | We use internal account IDs only; Play's "User IDs" covers identifiers that identify a person — `[confirm: answer No, as phone is already declared]` |
| Financial info → **Purchase history** | Yes | Required for paid plan | App functionality, Account management | Subscription status, product, Play purchase token |
| Financial info → Payment info, Credit score, Other | No | — | — | Payment is handled by Google Play |
| Health and fitness → **Health info** | Yes | Optional | App functionality, Personalization | Allergies; food needs such as low sugar |
| Health and fitness → Fitness info | No | — | — | |
| Messages → **Other in-app messages** | Yes | Optional | App functionality | Ticket messages between household and cook; Maharaj chat questions (sent to AI provider as a service provider) |
| Messages → Emails, SMS or MMS | No | — | — | OTP SMS is sent *to* the user, not read from the device |
| Photos and videos, Audio files, Files and docs, Calendar, Contacts | No | — | — | No such permissions |
| App activity → **Other user-generated content** | Yes | Optional | App functionality, Personalization | Menus, ratings, rating notes, stock and ration lists |
| App activity → **In-app search history** | Yes `[decision]` | Optional | App functionality | Maharaj questions act as searches; kept 30 days. If declared under Messages only, answer No here. |
| App activity → App interactions, Installed apps, Other actions | No | — | — | No analytics SDK |
| Web browsing | No | — | — | |
| Location → Approximate / Precise | No | — | — | Only time zone; IP used for abuse limits, not location |
| App info and performance → **Crash logs** | Yes **only if Sentry is enabled** | — | App functionality (Analytics is *not* selected) | Scrubbed of phone, tokens, names, IP |
| App info and performance → **Diagnostics** | Yes **only if Sentry is enabled** | — | App functionality | Device model, OS, app version |
| Device or other IDs → **Device or other IDs** | Yes | Required | App functionality, Fraud prevention, security & compliance | App-generated device id (X-Device-Id), FCM push token |

## 3. Data practices statements for the listing

Use in the store listing "About" or in a privacy highlights section:

- Your data is never sold and never used for ads.
- Maharaj chat questions go to an AI service without phone numbers or health needs.
- Delete your account or household any time in Settings (7-day undo).

## 4. Content rating (IARC questionnaire)

Category: **Reference, News, or Educational** `[or "All Other App Types"; the questionnaire offers the choice — Food & Drink apps usually take "All Other App Types"]`.

| Question | Answer |
|---|---|
| Violence, blood, gore | No |
| Fear / horror | No |
| Sexuality, nudity | No |
| Language (profanity, crude humour) | No |
| Controlled substances (drugs, alcohol, tobacco) | No `[confirm no recipes use alcohol as a featured ingredient; cooking with wine etc. would be "references to alcohol"]` |
| Gambling / simulated gambling | No |
| Does the app allow users to interact or exchange content? | **Yes** — household members and the cook can message each other on tickets (within an invited household only) |
| Does the app share the user's current physical location with other users? | No |
| Does the app allow users to purchase digital goods? | **Yes** — weekly subscription via Google Play |
| Does the app contain AI-generated content / a generative AI chatbot? | **Yes** — Maharaj replies are AI-worded, limited to cooking, post-validated `[answer if the questionnaire asks]` |
| Is the app a web browser or search engine? | No |
| Is the app primarily a news app? | No |

Expected rating: **Everyone / PEGI 3 / IARC 3+**, with interactive elements "Users Interact", "In-App Purchases".

Also in App content:

- **Ads:** No ads.
- **Target audience and content:** 18 and over. Not designed for children. App does not appeal to children unintentionally (no characters/games). 
- **News app:** No. **COVID-19 tracing:** No. **Government app:** No. **Financial features:** None.
- **Health apps declaration** (if shown): Not a medical device; does not provide medical advice; includes nutrition/diet-preference features `[pick the closest category — "Nutrition and weight management" may be over-claiming; reviewer to choose]`.

## 5. Privacy-policy URL plan

| Item | Value |
|---|---|
| Privacy policy URL (Play Console → App content → Privacy policy, and store listing) | **https://banega.kornea.in/privacy** |
| Terms URL (store listing / in app) | **https://banega.kornea.in/terms** |
| Account deletion web link (Data safety) | **https://banega.kornea.in/privacy#delete-account** |
| Source files | `docs/legal/site/privacy.html`, `docs/legal/site/terms.html` (self-contained, no scripts). Rebuild from the markdown with `python docs/legal/site/build_site.py` (drops `[Note]` blocks, highlights placeholders). |
| Hosting | Static hosting on the `banega.kornea.in` subdomain (`[e.g. a static location in the nginx container, or any static host]`). Serve `/privacy` → `privacy.html` and `/terms` → `terms.html` over HTTPS, publicly reachable without login, with no geo-blocking. |
| In-app links | Settings → Privacy policy and Terms rows, and the consent screen link, open these URLs (`app/lib/core/config.dart`: `kPrivacyPolicyUrl`, `kTermsUrl`; override with `--dart-define=BANEGA_PRIVACY_URL=…` / `BANEGA_TERMS_URL=…`) |
| Before submission | Pages must be live (Play crawls the URL), must name Kornea as the developer, and must match the Data safety answers. Remove all `[Note]` blocks and fill placeholders. |
