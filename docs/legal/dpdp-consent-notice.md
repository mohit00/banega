# Banega DPDP Consent Notice

> **DRAFT — must be reviewed by a qualified Indian lawyer before publishing.**
> This is the short, itemised notice under section 5 of the DPDP Act, 2023, shown on the first-run consent screen before any household data is entered. Notes for the reviewer are in `[Note: …]`.

> **Short mein (Hinglish summary)**
> Pehli baar app kholne par ek screen aati hai: kya data, kis kaam ke liye, AI ko kya jaata hai, bachchon ki profile, aur aapke haq. "Maan liya" dabane par version `2026-09` aur samay save hota hai. Settings → "Consent dobara padho" se kabhi bhi dobara padh sakte ho.

---

## 1. How consent works in the app today (from the code)

- Screen: `ConsentScreen` (`app/lib/features/account/presentation/consent_screen.dart`), shown after Splash and before the Family step, and again from **Settings → Privacy & data → Review consent**.
- Tapping **I agree / Maan liya / मान लिया** stores the version on the device and calls `POST /v1/consent` with `version: "2026-09"`. The backend stores one `consents` row per user and version (`backend/app/models/feedback.py`). `GET /v1/consent` reports `required: true` when the user has not accepted the current version.
- Changing the notice materially = bump `CONSENT_VERSION` (backend `app/core/config.py`) and `kConsentVersion` (app) together, so every user sees the new notice. **This change does not bump the version** (wording made more accurate; purposes unchanged). `[Note: the reviewer should decide whether the wording change below counts as a material change; if so, bump to "2026-10" in both places.]`
- The screen links to the full Privacy Policy at `https://banega.kornea.in/privacy` (constant `kPrivacyPolicyUrl`, overridable with `--dart-define=BANEGA_PRIVACY_URL=…`).

## 2. The itemised notice (purpose-wise)

**Data Fiduciary:** `[KORNEA LEGAL ENTITY NAME]`, contact anshul@kornea.in. Grievance Officer: `[GRIEVANCE OFFICER NAME / EMAIL]`.

| # | Purpose | Personal data used |
|---|---|---|
| 1 | Log you in and keep the account secure | Phone number, OTP, device identifier |
| 2 | Suggest meals that suit everyone | Family members' names, diet, allergies, food needs, vrat days, dislikes, spice, cuisines |
| 3 | Send menus to your cook and run the kitchen | Menus, who is eating, tickets, ticket messages, stock, ration requests, cook name and phone |
| 4 | Maharaj chat (AI) | Your typed question, plus anonymised family constraints, sent to Anthropic's Claude API (United States). Never phone numbers or health needs; allergies only as counts; a family name only if you typed it |
| 5 | Learn from ratings | Dish ratings per member |
| 6 | Notifications | Push token, notification preferences |
| 7 | Subscription and one free trial per phone/device | Google Play purchase status, phone number, device identifier |

**Children:** you add children's profiles as their parent or guardian. Children do not log in.

**Your rights:** access (export), correction, erasure (delete account or household from Settings; 7-day undo), withdraw consent (delete your account), nominate someone, and complain to our Grievance Officer and then to the Data Protection Board of India.

**Never:** we never sell your data or use it for ads.

## 3. In-app copy (exact strings)

The screen has six strings. Keys are unchanged. The current strings were mostly accurate; two were changed because they were **less accurate than the code**:

- `consentLlmNote` said names are **not** sent to the AI. In fact (`backend/app/services/maharaj/parse.py`, `write.py`) the typed question is sent as written, and a member's name reaches the AI when the user typed that name. Health needs are never sent; allergies go only as anonymous counts.
- `consentBody` did not mention the phone number (login, OTP, trial check) and said "you can export … any time", but export is admin-only (`POST /v1/export` needs the edit-household permission).

`consentTitle`, `consentKids`, `consentAccept` and `consentPrivacy` were accurate and are unchanged.

### English (`app_en.arb`)

| Key | Text |
|---|---|
| consentTitle | Your data, your choice |
| consentBody | Banega uses your phone number to log you in, and your family's preferences, allergies, fasting days and meal history only to plan menus, send tickets to your cook and power Maharaj's suggestions. Your data is never sold. You can delete your account any time from Settings, and the household admin can export or delete the household's data. |
| consentLlmNote | Maharaj chat questions are sent to an AI service (Anthropic's Claude). Phone numbers and health needs are never sent; allergies go only as counts, and a family member's name only if you type it. |
| consentKids | You add kids' profiles as their parent or guardian. |
| consentAccept | I agree |
| consentPrivacy | Read the privacy policy |

### Hinglish (`app_hi_Latn.arb`, the template locale)

| Key | Text |
|---|---|
| consentTitle | Aapka data, aapka haq |
| consentBody | Banega aapka phone number login ke liye, aur ghar ke members ki pasand, allergy, vrat ke din aur khaane ka itihaas sirf menu banane, cook ko ticket bhejne aur Maharaj ke sujhav ke liye rakhta hai. Data kabhi becha nahi jaata. Settings se kabhi bhi apna account delete kar sakte ho; ghar ka admin poore ghar ka data export ya delete kar sakta hai. |
| consentLlmNote | Maharaj chat ke sawaal ek AI service (Anthropic Claude) ko jaate hain. Phone number aur health needs kabhi nahi jaate; allergy sirf ginti mein, aur family ka naam sirf tab jab aap khud likho. |
| consentKids | Bachchon ki profile aap maa-baap ya guardian ki tarah bana rahe ho. |
| consentAccept | Maan liya |
| consentPrivacy | Privacy policy padho |

### Hindi (`app_hi.arb`)

| Key | Text |
|---|---|
| consentTitle | आपका डेटा, आपका हक |
| consentBody | बनेगा आपका फ़ोन नंबर लॉगिन के लिए, और घर के सदस्यों की पसंद, एलर्जी, व्रत के दिन और खाने का इतिहास सिर्फ मेन्यू बनाने, कुक को टिकट भेजने और महाराज के सुझाव के लिए रखता है। डेटा कभी बेचा नहीं जाता। सेटिंग्स से कभी भी अपना अकाउंट डिलीट कर सकते हो; घर का एडमिन पूरे घर का डेटा एक्सपोर्ट या डिलीट कर सकता है। |
| consentLlmNote | महाराज चैट के सवाल एक AI सेवा (Anthropic Claude) को जाते हैं। फ़ोन नंबर और सेहत से जुड़ी ज़रूरतें कभी नहीं भेजी जातीं; एलर्जी सिर्फ गिनती में, और परिवार के किसी सदस्य का नाम सिर्फ तब जब आप खुद लिखें। |
| consentKids | बच्चों की प्रोफ़ाइल आप माता-पिता या अभिभावक की तरह बना रहे हो। |
| consentAccept | मान लिया |
| consentPrivacy | प्राइवेसी पॉलिसी पढ़ो |

## 4. Open points for the reviewer

1. **One tap, many purposes.** DPDP section 6 asks for consent that is specific to each purpose. The screen lists purposes but takes a single "I agree". Decide whether purpose 4 (AI) needs its own toggle; if declined, the app could use the rule-based parser only (the code already supports running without the AI).
2. **Notice in the user's language.** The DPDP Act requires the option to read the notice in English or any Eighth Schedule language. The app offers English, Hinglish and Hindi; Hinglish is not an Eighth Schedule language, but Hindi and English are.
3. **People who never see the screen.** Profile-only members (including children) and a hired cook operated "via admin" never see this notice. The Terms put the duty to inform them on the admin. A cook who logs in with their own phone does see it, but the copy is family-oriented; consider a cook-specific line (FRD F-X-02 asks for "its own notice at cook onboarding").
4. **Withdrawal.** Withdrawal today = delete account. Consider a "Withdraw consent" row that explains this.
5. **Proof of consent after deletion.** Consent rows are deleted when the account or household is purged. Decide whether a minimal record (version, time, hashed user id) must be kept as evidence.
