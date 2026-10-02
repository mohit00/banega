# Banega — Flutter app

"Aaj khaane mein kya hai?" Family meal planner with AI Maharaj. This is the
Phase 1 build: design system, onboarding (Splash → Family → Prefs → Loading)
and a Home placeholder, running on the prototype's in-memory demo family.

The design reference is `../design/prototype_*.{html,css,js}` and
`../docs/build-plan.md` §1.

## Run

Flutter is not on PATH on the dev machine, so call it by full path
(PowerShell):

```powershell
cd C:\Users\PC\Desktop\banega\app
& "D:\DevTools\flutter\bin\flutter.bat" pub get
& "D:\DevTools\flutter\bin\flutter.bat" devices            # list device ids
& "D:\DevTools\flutter\bin\flutter.bat" run -d <device>    # e.g. -d emulator-5554
```

Checks:

```powershell
& "D:\DevTools\flutter\bin\flutter.bat" analyze
& "D:\DevTools\flutter\bin\flutter.bat" test
& "D:\DevTools\flutter\bin\cache\dart-sdk\bin\dart.exe" format -l 120 lib test
```

Localizations are generated on `pub get` / build (`flutter: generate: true`).
To regenerate by hand: `flutter gen-l10n`.

## Layout

```
lib/
  app.dart, main.dart       MaterialApp.router + ProviderScope
  core/
    theme/tokens.dart       colours, radii, heights, type scale, shadows (build-plan §1.2)
    theme/theme.dart        BText (Figtree / Bricolage Grotesque styles) + ThemeData
    motion/motion.dart      durations/curves from the prototype + reduce-motion
    router/                 go_router: /splash /family /prefs/:memberId /loading /home (+ stubs)
    engine/fit_engine.dart  port of the prototype's fitFor / summarize / constraintLine
    l10n/arb/               app_hi_Latn.arb (template, Hinglish), app_en.arb, app_hi.arb
    l10n/gen/               generated AppLocalizations (do not edit)
  ui/                       design-system components (§1.3) + gallery/ (route /gallery)
  features/
    onboarding/             SplashScreen
    members/                Member model, repository (demo), Riverpod controller, Family + Prefs
    home/                   LoadingScreen, HomeScreen (Phase 3 placeholder body)
    recipe/                 Recipe model
  labels/                   enum + engine-reason → locale string mapping
  data/demo/                demo members, member pool and the 22 seed recipes
```

## Notes

- **Locale.** Hinglish is the template locale, coded `hi_Latn`
  (`app_hi_Latn.arb`). `app_en.arb` (English) and `app_hi.arb` (Hindi,
  Devanagari) are translated; `test/l10n_test.dart` fails on a value left in
  Hinglish (allow-lists for brand names and formats). The app pins `hi-Latn` via `localeProvider` in `app.dart`;
  set it to `null` to follow the device once en/hi are translated.
- **Fonts** are bundled (no runtime fetching): Figtree, Bricolage Grotesque
  and Noto Sans Devanagari, all variable TTFs from github.com/google/fonts
  (OFL; licences in `assets/fonts/`). Weights go through the `wght` axis
  (`BText` sets `fontVariations`); Bricolage's `opsz` follows the font size.
  Noto Sans Devanagari is the fallback for Hindi script.
- **Motion.** All animations read `Motion.reduce(context)`
  (`MediaQuery.disableAnimations`): entrances become instant, loops stop.
  The 1.9 s loading hold is functional and is not shortened.
- **Thali.** The prototype's splash uses a thali photo; the app draws a
  lightweight painted thali (`ui/thali_hero.dart`) instead — no image assets.
- **Tests.** Looping animations never settle, so tests advance time with
  `pump(duration)` rather than `pumpAndSettle`. The test font is wider than
  Figtree, so components ellipsize rather than overflow.

## Data sources, auth and startup

- **Sandbox vs API.** With no `BANEGA_API_BASE_URL` the app is the demo
  sandbox. With one, it is API mode, and the sandbox is only entered on
  purpose from Splash ("Demo family ke saath dekho", which also passes
  consent). API mode never falls back to demo data. A network failure shows
  the offline banner and retry buttons (Home / Plan / Chat / cook mode). The
  "Demo data" pill shows only in the sandbox.
- **One API client** (`data/data_source.dart` `dioProvider`): the
  `Accept-Language` and `X-Request-Id` headers, bearer auth with a
  single-flight refresh on 401 that replays the request and logs out when the
  refresh is rejected (`core/network/api_client.dart`). Every repository maps
  failures through `ApiGuard` → the sealed `AppError`
  (`core/network/app_error.dart`).
- **Login**: OTP (`/phone` → `/otp`). Tokens go in `flutter_secure_storage`.
  A dev backend (`ENV=dev`) returns the code, and debug builds show it on the
  OTP screen. A user without a household names one (`/household/new`, "…
  Parivaar"), then sets up the family.
- **Startup gate** (`core/router/startup_gate.dart`): a GoRouter redirect
  over the auth state, consent, `onboarding.done` and the cached `/v1/me`.
  Signed out → Splash on first launch, else `/phone`. No consent →
  `/consent`. No household → create one. Hired cook → `/cook`. Otherwise
  `/home`.
- **Clock**: "today" and the default slot follow the household timezone
  (`Household.timezone`, default Asia/Kolkata; the sandbox uses device time).
  The day rolls over at 04:00, so 00:00–03:59 still counts as the previous
  day's Dinner. The clock ticks at 00:00, at 04:00 and on resume.
- **Offline cook mode**: the cache is scoped by user and household. Entries
  expire after 3 days and are purged on logout or account deletion.
  `SyncService` replays queued writes one run at a time when connectivity
  returns, on resume and when K1 loads. A 409/412/422 (or another 4xx) drops
  the write and the cook gets a toast. Offline, 5xx, 408 and 429 keep it
  queued.
- **Device-only member fields**: vrat days and "show health on Home" have no
  API field yet. They are stored on the device (`member.local.<id>`).

## Family invites and chef for the day

- **Invite a second adult** (admin): Settings → "Banega par parivaar" lists
  pending invites (masked phone, expiry, revoke) and "Parivaar ke kisi ko
  bulao" opens a sheet: pick an existing profile or a new member, the phone
  (+91), then the 6-character code with "WhatsApp par bhejo" (the server's
  share text) and copy (`features/invites/`).
- **Join with a code** (invitee): a signed-in user without a household sees
  "Code se judiye" under "Ghar banao" → `/household/join` (six boxes, like
  the OTP) → `POST /v1/invites/accept-code` → `/v1/me` refresh → Home. Wrong,
  expired, other-number, already-in-a-household and locked codes each get
  their own message.
- **Unassigned tickets**: the Home ticket card says "Kaun banayega?"; the
  ticket detail lets the admin assign a cook (hired → `new`, family →
  `accepted`, with `assignee_cook_id`) and any adult take it as chef for the
  day ("Main banaunga", `POST /claim`; a lost race shows a toast). After a
  claim `/v1/me` is refetched, so the Rasoi tab appears. Inbox
  `ticket_unassigned` / `no_show` items open the ticket.
- **Chat chips** follow the app language: the server localizes them from
  `Accept-Language`, and known Hinglish chips are translated on the device
  as a fallback (`ChatLabels.localizeChip`).

## Crash reporting (optional)

Sentry is off unless the build passes a DSN:

```powershell
& "D:\DevTools\flutter\bin\flutter.bat" build appbundle --release --dart-define=SENTRY_DSN=https://<key>@<org>.ingest.sentry.io/<project> --dart-define=SENTRY_ENVIRONMENT=production
```

With no DSN `runWithCrashReporting` (`lib/core/crash_reporting.dart`) just runs
the app. With one, `beforeSend` / `beforeBreadcrumb` mask phone numbers, JWTs,
bearer tokens and OTP / invite codes, drop request bodies, cookies and
headers, and keep only the user's id; screenshots and PII are off. Tests run
without a DSN (`test/crash_reporting_test.dart`).

## Release signing (Android)

`android/key.properties` (git-ignored) points at the upload keystore:

```properties
storeFile=../banega-upload.jks
storePassword=...
keyAlias=...
keyPassword=...
```

`storeFile` is relative to `android/app/`. `flutter build appbundle --release`
(what Play takes) fails without this file or with a missing field / keystore;
a release APK without it is debug-signed with a warning (local testing only).
Keep the keystore and its passwords backed up outside the repo: losing the
upload key means a key reset through Play Console.

## Push notifications (FCM)

- `android/app/google-services.json` (Firebase project `banega-fb1ed`, Android
  app `in.kornea.banega`; not secret, tracked) is turned into resources by the
  `com.google.gms.google-services` Gradle plugin, which is applied only when
  the file exists. Without it the app still builds and push stays off.
- At runtime (`lib/core/push/`): API mode + signed in → `Firebase.initializeApp`
  (fails quietly without the config) → notification permission (Android 13+,
  `POST_NOTIFICATIONS`) → `POST /v1/devices {platform: android, push_token}`,
  again on every token refresh. Logout → `DELETE /v1/devices/{id}` before the
  session ends, then the FCM token is deleted. A foreground message refreshes
  the ticket views. Tapping a notification opens `ticket_id`'s ticket (cook mode
  for a hired cook), else the inbox (K1 for a hired cook); on a cold start it
  waits until Home / K1 is shown.
- `--dart-define=FCM=0` builds without push.
- Adding the Android app in Firebase: package `in.kornea.banega`, SHA-1 and
  SHA-256 of the upload key and the debug key (`keytool -list -v -keystore
  android/banega-upload.jks`); after Play App Signing is on, also add the
  app-signing key's SHA-256 from Play Console → App integrity.

## Store billing (Google Play)

API mode on Android uses `PlayBillingAdapter` (`in_app_purchase`): product
`banega_weekly_50`, base plan `weekly`. Purchase → the Play purchase token →
`POST /v1/subscription/restore {store: play, purchase_token}` (the server
verifies and acknowledges it) → `completePurchase`. Restore asks Play for owned
purchases. Pending payments (UPI) show a "pending" toast and are posted by the
background listener when they complete; cancel and errors get their own toasts.
The sandbox keeps `DemoBillingAdapter`; other platforms have no store billing
yet. Tests use a fake `StoreClient` (`test/push_billing_test.dart`).

Debug-only surfaces: the design gallery (`/gallery`) and the demo cook-role
switch in Settings exist only in debug builds.

## Tests

- `flutter test` runs everything, including the 200% text sweep
  (`test/text_scale_test.dart`) and the screen goldens
  (`test/golden_test.dart`, 390×844, images in `test/goldens/`).
- Regenerate the goldens after an intended visual change with
  `flutter test --update-goldens test/golden_test.dart`. They are rendered on
  Windows, so compare them on the same OS.

## TODO (deferred)

- **Push on iOS**: `GoogleService-Info.plist` + APNs key.
- **Durable cache**: move the offline cache and outbox from
  shared_preferences to drift (per-row outbox, migrations).
- **Store billing on iOS**: App Store (StoreKit + App Store Server API).
