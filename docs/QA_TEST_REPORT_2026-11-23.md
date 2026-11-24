# Om Sai Ram QA Test Report

**Run ID:** QA-2026-11-23-03
**Execution date:** 2026-11-23 to 2026-11-24
**Catalogue:** [QA_TEST_CASES.md](QA_TEST_CASES.md), 243 test IDs
**Tested revision:** `f109fada8d3e2c388d67e824f379f26e60f8466b` plus uncommitted changes
**Overall recommendation:** **LOCAL GATES PASS; RELEASE VALIDATION PENDING**

## Executive Summary

The complete locally executable automated test surface was run across the Flutter client, Firebase Auth/Firestore rules and integration modules, Firebase Functions, the FastAPI fallback, and bundled multilingual content. All five core automated suites passed: **3,158 checks passed and none failed**.

Build verification also passed for debug/release web and debug/release Android APK targets. A mobile-size Chrome smoke test loaded all eight public routes without console errors and visually confirmed the compact Help control and requested seven-tile home order.

The separate FastAPI safety-oracle probe mapped to the QA catalogue also passed all **991/991 checks** after the reproduced authentication, scheduling, chat, input-boundary, and CORS findings were fixed. Flutter analysis is clean, and the refresh-token migration/concurrency path passed against PostgreSQL 16. Release is still not fully certified: the 243-case catalogue includes device, production Firebase, broader database, notification, cross-browser, accessibility, and human-language scenarios that this local environment cannot certify. Automated success must not be interpreted as all 243 catalogue cases passing.

Machine-readable evidence:

- [Environment](test-results/QA_RUN_2026-11-23_ENVIRONMENT.json)
- [Results](test-results/QA_RUN_2026-11-23_RESULTS.json)

## Scope and Method

The run covered both application implementations in the repository:

- The Flutter app and its default Firebase-backed services.
- Firebase emulator rules and domain modules.
- Firebase Functions units.
- The FastAPI/SQLAlchemy fallback backend.
- Structural integrity of the 18 bundled-language chapter assets.

The Firebase app is the default runtime. The resolved FastAPI findings below applied to the fallback backend and did not imply that the corresponding Firebase path failed.

The analyzer-clean follow-up was tested from commit `5bd1ed7` plus 42 tracked modifications. No production credentials, live Firebase project, deployment, or destructive production operation was used.

## Automated Results

| Surface | Result | Passed | Failed | Notes |
|---|---:|---:|---:|---|
| Flutter unit/widget tests | Pass | 2,459 | 0 | 92.743 s |
| Firebase emulator/rules integration | Pass | 382 | 0 | 223.041 s; isolated demo emulators |
| Firebase Functions unit tests | Pass | 75 | 0 | 0.578 s |
| FastAPI pytest | Pass | 97 | 0 | 38.42 s; two Pydantic deprecation warnings |
| Content structural checks | Pass | 145 | 0 | 18 languages, 852 chapters |
| **Core suite total** | **Pass** | **3,158** | **0** | No skipped tests reported |
| FastAPI catalogue safety probes | **Pass** | 991 | 0 | Partial API evidence across 101 catalogue IDs |
| Flutter analyzer | Pass | n/a | 0 | 0 errors, 0 warnings, 0 infos; exit 0 |

The final Firebase run used the repository wrapper to start isolated `demo-om-sai-ram` Auth and Firestore emulators, execute all 382 tests, and shut the emulators down cleanly. Permission-denied emulator log entries were expected negative authorization assertions.

## Build Results

| Target | Result | Duration | Observed artifact size |
|---|---:|---:|---:|
| Flutter web, debug | Pass | 108 s | 89 MB directory |
| Flutter web, release | Pass | 74 s | 74 MB directory |
| Android APK, debug | Pass | 23 s | 198 MB |
| Android APK, release | Pass | 77 s | 76 MB |

The debug web target was rebuilt after release validation, so `om_sai_ram/build/web` currently contains the emulator-mode QA build. The APKs remain at `om_sai_ram/build/app/outputs/flutter-apk/`.

## Browser Smoke

Chrome 145 was tested at a 390 x 844 mobile viewport against the local debug build. The following public routes loaded with no console errors:

`/`, `/reader`, `/audio`, `/live`, `/events`, `/daily-programme`, `/faq`, `/jaap`

The final home check confirmed:

- A compact question-mark Help control in the top controls.
- Home tiles ordered as Read Satcharita, My Groups, Live Darshan, Listen, Daily Programme, Upcoming Events, Naam Jaap.
- The emulator safety banner was visible in the debug build.
- The release build without project defines showed the expected Firebase configuration guidance instead of silently connecting to an emulator or cloud project.

Requests cancelled by immediate navigation away from the Live and Events screens were browser-navigation aborts; no console error or failed smoke assertion resulted.

## Resolved Findings

The post-fix catalogue probe reproduced no open API findings. This run verified:

- One-time refresh-token rotation, replay rejection, and password-change revocation for prior access and refresh tokens.
- Controlled rejection of unsafe manual week values.
- Explicit scheduling overflow accounting, hint validation, round-robin wrapping, and preview/confirmation consistency.
- Stable chat pagination for tied timestamps plus rejection of missing and cross-group cursors.
- Restricted default CORS behavior with deployment-specific origin configuration.

The new refresh-token state passed Alembic upgrade, downgrade and re-upgrade against an ephemeral PostgreSQL 16 database. Default values, index creation and `ON DELETE CASCADE` were verified. Two simultaneous refresh exchanges produced exactly one 200 and one 401; password change revoked prior access and refresh tokens, and a new-password login succeeded.

## Not Certified in This Run

The following catalogue areas remain blocked or manual, not passed:

- Physical Android phone/tablet layout, permissions, background audio, notification delivery, and assistive-technology behavior.
- Real Firebase Auth providers, SMS, cloud deployment, production Functions, and production security configuration.
- PostgreSQL restore and full domain cascade/concurrent-write guarantees beyond the certified refresh-token path.
- Firefox, Safari, Edge, iOS/iPadOS, hosted SPA deep-link refresh, and adverse-network matrices.
- Qualified human review of translation, OCR, punctuation, and source-text accuracy across all 18 languages.

## Release Decision

The locally executable automated, analyzer, build, and targeted PostgreSQL gates pass, including all 991 FastAPI catalogue checks. Production promotion still requires the production/device/manual cases relevant to the intended launch platform.
