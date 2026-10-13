# Om Sai Ram — Flutter App

Flutter client for individual and group Shri Sai Satcharita reading. State is managed with Riverpod; GoRouter handles public/private navigation; Dio connects to the FastAPI API.

## Documentation

- [Requirements specification](../docs/REQUIREMENTS.md)
- [Project overview](../README.md)
- [User guide](../docs/USER_GUIDE.md)
- [QA test plan and cases](../docs/QA_TEST_CASES.md)
- [Backend configuration and API](../backend/README.md)

## Run locally

Use a current compatible Flutter stable SDK. [pubspec.yaml](pubspec.yaml) declares Dart3; dependency/plugin requirements may need a newer Flutter release than the original project minimum.

From this directory, run `flutter pub get`, choose a target with `flutter devices`, then run `flutter run`. Android and web platform files are already checked in; do not regenerate them as a routine setup step.

Set the API host using `--dart-define=API_BASE_URL=http://HOST:8000` when running/building. The default is `http://localhost:8000`; Android emulator/device localhost is not the development machine. Use an address reachable from the target. Production needs HTTPS and backend CORS configuration for its web origin.

Android and web are the checked-in targets. iOS/iPadOS and desktop need platform generation, signing/toolchains, plugin configuration and independent testing before support can be claimed.

## Main flows

- Guest access: home, reader, media/live, events, daily programme and FAQ.
- Login required: groups and profile; email/password works, phone is a development OTP flow, provider verification for Google/Apple is incomplete.
- Group Schedule: admins/leads can **Manual Assign** one/multiple chapter units to a member/week, or use **Auto-Schedule** and suggestions.
- Combined readings:16–17,18–19,43–44,51–53 are one group assignment. Marathi group reading assembles originals; standalone Marathi remains separate.
- Reader: offline bundled text, per-language cache, search, bookmarks, font settings, resume/local history and group completion flow.
- Local reminders: native daily verses and group reading schedules; not server push or guaranteed web notifications.

## Source layout

| Path | Purpose |
|---|---|
| [lib/main.dart](lib/main.dart) / [lib/app.dart](lib/app.dart) | Startup, root theme/providers |
| [lib/core/](lib/core/) | API/router/storage, localization, language/reading preferences, notifications, constants |
| [lib/features/](lib/features/) | Auth, groups/manual scheduling, reader, audio/live, profile, dashboard, events, FAQ/info |
| [lib/shared/](lib/shared/) | Shared app shell/widgets |
| [assets/content/](assets/content/) |18 bundled books:53 Marathi entries,47 entries per translation |
| [assets/i18n/](assets/i18n/) | Localization resources |
| [web/live_player.html](web/live_player.html) | Web live-stream player |
| [test/](test/) | Smoke, combined-reading and manual-assignment tests |

## Content and identity rules

Keep original numbers1–53; group scheduling has48 units because four ranges count once. Chapter50 stays a separate Marathi-fallback assignment. The manual picker fetches the actual server chapter IDs; do not substitute bundled IDs or original numbers for database IDs.

There are17 selectable languages; Urdu is disabled and some languages are beta for OCR/content quality. App-language changes synchronize reader language initially; reader language can then be selected independently.

Local settings/bookmarks/history are stored on the installation/browser, not guaranteed cloud-synced or account-separated. Group data/progress are server-backed. Content can work offline while group writes cannot.

## Media and platform notes

- Release web audio requires the manual plugin registration in [lib/register_web_plugins.dart](lib/register_web_plugins.dart), selected through the conditional import. Test release playback explicitly.
- Native chapter playback downloads/caches audio; web streams without native filesystem access.
- External audio URLs and Live Darshan can fail independently of the app. Browser gestures/codec/WebView support affect playback.
- Local notifications need native permission and real-device testing, including timezone/DST. Unsupported-platform calls must not break core screens.
- A stale generated Linux build is not evidence that Linux is supported. Install required native tools/configure that target before testing it; avoid deleting unrelated build state during routine documentation/setup work.

## Tests and quality checks

Run `flutter test` for the full suite and `flutter analyze` for diagnostics. Existing tests cover basic root rendering, combined labels/Marathi assembly and manual member/week selection, server IDs, errors/retry, partial saves and keyboard layout.

Use the [QA catalogue](../docs/QA_TEST_CASES.md) for end-to-end permissions, real connectivity, release builds, content review, notifications, accessibility and platform certification. Unit/widget tests alone do not certify these behaviors.

For release packaging, use the standard Flutter Android/web build workflow with the production API define; signing, HTTPS hosting, SPA deep-link fallback and browser/API origins must be configured for the target environment. See the QA release gate before distribution.
