# Om Sai Ram — QA Test Plan and Test Cases

**Document version:** 1.0  
**Source-review date:** 2026-10-13  
**Scope:** Flutter client, FastAPI API, PostgreSQL, bundled scripture, external media, local notifications, and deployment.  
**Execution status:** This is a test specification, not a test-results report. All catalogue cases start **Not Run**. Existing automated tests do not establish that these manual/end-to-end cases passed.

**Catalogue:** 243 cases across 20 feature families: 101 P0, 139 P1 and 3 P2. Parameterized language, role, platform and data-boundary runs expand this base count.

**Requirements baseline:** [Software requirements specification](REQUIREMENTS.md). Its requirement tables link to representative cases/families in this catalogue; approval and test execution remain separate activities.

## Contents

1. [Strategy and acceptance](#strategy-and-acceptance)
2. [Environment and test data](#environment-and-test-data)
3. [Verified rules and limitations](#verified-rules-and-limitations)
4. [Permissions matrix](#permissions-matrix)
5. [Test-case catalogue](#test-case-catalogue)
6. [Traceability and automation](#traceability-and-automation)
7. [Execution and defect reporting](#execution-and-defect-reporting)

## Strategy and acceptance

### Priority

- **P0:** Release-critical: account access, authorization, chapter assignment integrity, reading content, destructive operations.
- **P1:** Essential: routine feature behavior, recovery, persistence, accessibility, configuration.
- **P2:** Secondary: presentation, optional features, less frequent combinations.

Priority is test importance; it is not automatically the severity of a defect.

### Layers

- **UI:** Manual/device, Flutter widget, or UI integration execution.
- **API:** Direct HTTP requests with controlled fixtures; verify response and database state.
- **E2E:** Real client plus API and PostgreSQL, preferably using two independent users/devices.
- **DATA:** Bundled JSON, content/index integrity, and source comparison.
- **OPS:** Installation, configuration, build, recovery, and release verification.

Each catalogue row specifies the action and observable expected result. Apply the common fixtures below unless the row overrides them. Repeat parameterized rows for **every** listed value. A row can produce multiple execution records.

### Entry criteria

1. Record the commit, app build number, API build, database/migration version, device/browser/OS, locale, timezone, and network profile.
2. Use an isolated test database and synthetic identities. Do not use production credentials, phone numbers, or devotional reading history.
3. Seed the chapter index and test groups; make server chapter IDs deliberately different from chapter numbers for identity tests.
4. Identify which external services are real versus stubbed. Provide fixtures for unavailable services.
5. Agree on target platforms and measured performance budgets before execution.

### Exit criteria

- All applicable P0 cases pass; no unresolved critical/high-impact authorization, data-loss, content-integrity, or crash defects.
- All applicable P1 cases execute; exceptions require a written owner, impact assessment, and release sign-off.
- Full automated suites pass; failures are investigated, not skipped silently.
- Core flows pass on release builds, not only debug builds; offline, expired-session, denied-permission, and accessibility runs are complete.
- Unsupported integrations are accurately disclosed or disabled; production SMS and social authentication require separate readiness approval.
- Localization/content quality is signed off by readers competent in the language; OCR output alone is not sufficient.

### Smoke pack

For each build execute **NAV-01, AUTH-01, AUTH-07, AUTH-15, GRP-01, GRP-05, MAN-01, MAN-04, COM-01, SCH-01, READ-01, READ-06, PROG-01, CHAT-01, MEDIA-01, LIVE-01, SEC-01, OPS-01**. Use stubs/Blocked where live integrations are unavailable, not fabricated passes.

## Environment and test data

### Platform matrix

| Target | Minimum execution | Important distinction |
|---|---|---|
| Android phone | Debug and release; minimum configured supported OS and current stable OS; small and large screens | Permission denial, background/idle restrictions, downloaded audio, actual notification delivery |
| Android tablet | Portrait, landscape, large text | Sheets, keyboard, navigation and reader layout |
| Web | Release build on current Chrome/Edge, Firefox and Safari where available; desktop and mobile sizes | Streaming audio, autoplay gestures, CORS, refresh/deep links, HLS/codec support; do not assume native notifications |
| iOS/iPadOS | Conditional: generate/configure the platform and certify on macOS before claiming support | No iOS project is checked in; Apple auth/backend verification is incomplete; permissions and audio need real-device certification |
| Linux desktop | Conditional platform/build test | No Linux project is checked in; native toolchain and plugin support need verification; do not claim parity |

The checked-in application targets are **Android and web**. Flutter framework portability is not evidence of a tested platform.

### Fixtures

| Fixture | Definition |
|---|---|
| Guest | No token, cleared app storage |
| A | Email user; admin of G1 and ordinary member of G2 |
| L | Group lead of G1; not an admin |
| M1/M2 | Ordinary G1 members on separate devices/sessions |
| X | Authenticated outsider to G1 |
| P | Phone-only user with controlled test OTP |
| D | Anonymized/deleted user with old access and refresh tokens |
| G1 | Chapter-wise group, initially current week 1 and two readings/member/week; adjust explicitly per case |
| G2 | Second group for cross-group isolation and Saptah-label testing |
| Chapter index | Numbers 1–53; real server IDs, including IDs not equal to numbers; Marathi index plus English-only legacy fixture |
| Assignments | Not-started, in-progress and completed; current, past and future weeks; one legacy split-range schedule |
| Network | Normal, offline, high latency, intermittent connectivity, HTTP 401/403/404/422/429/500, media 404 and timeout |
| Clock | UTC, Asia/Kolkata and a DST timezone; near midnight, Monday boundary and DST transitions |
| Content | All 18 bundled language codes, 17 selectable languages; beta-language and missing-chapter fixtures |

Use dedicated setup/teardown for each case. Reset in-process rate-limit state between unrelated auth tests. Save cleanup requirements for audio downloads, scheduled notifications, fixtures and anonymized users.

## Verified rules and limitations

### Rules that test expectations must preserve

- Original numbering is **53 Marathi adhyayas**. Group reading units are **48**: **16–17, 18–19, 43–44, 51–53** count once each; 50 remains separate and may fall back to Marathi.
- Non-Marathi bundled books currently have 47 entries. Marathi has 53. Neither count should be substituted for the 48 group reading units.
- Group assignments assemble the separate Marathi originals for a combined unit. Standalone Marathi reading keeps them separate.
- Manual assignments reject same-member/same-group/**same-week** duplicates across a combined range. The same reading can be assigned again in a different week.
- Automatic scheduling skips existing same-member/same-week units. Existing saved split-range schedules are **not automatically migrated**.
- Default manual reading dates are Monday of the chosen week relative to the group's current week; explicit dates are preserved. Automatic dates use the current reference Monday.
- API authorization is authoritative. Admins and leads can assign; only the assignee can change reading status. Group settings, role changes and group deletion are **admin-only**, even if a lead is offered a control in the UI.
- Supported statuses are `not_started`, `in_progress`, `completed`. Current API permits changing back to a previous status; do not assume a one-way state machine.
- Names: API strips whitespace, accepts 1–255 characters; group-name UI accepts 2–80; generic required-field UI has a 100-character maximum. Record these differences explicitly.
- Passwords: 8–128 characters; no configured complexity requirement. Invite code: generated length 6; API accepts 4–8; UI accepts 4–20. UI/API disagreement is a test target, not a new requirement.
- Login API limits failed attempts to 10 per 15 minutes; send-OTP limits 5/hour; OTP verification limits failed attempts to 5 per 10 minutes. Limits are process-local. A UI throttle, if shown, is separate from API enforcement.
- OTPs generated by the backend are 6 digits and expire in 10 minutes. UI requires 4–8 numeric digits; the API schema currently validates length, not digit-only format.
- Changing app language synchronizes reader language; changing reader language afterwards does not change UI language. There are 18 bundled languages; Urdu is disabled in the chooser; eight language enums have beta flags, seven of them selectable.

### Known limitations and risk-based oracles

These are not silent exclusions. Cases targeting a desired safety property should be recorded **Fail** if reproducibly violated, or **Blocked** if the integration/environment cannot be exercised.

| Risk | Current observation | How to test/report |
|---|---|---|
| Social sign-in | Client buttons/packages exist; Google backend returns 501, Apple reaches a 400 extraction error; provider-token verification is not implemented | Verify controlled error and no account/token creation. Successful social E2E is Blocked until implementation/configuration is approved |
| SMS delivery | OTP is logged server-side; no production SMS sender | Use a controlled fixture for API tests; real delivery is Blocked. OTP plaintext in production logs is a security defect |
| Session revocation | JWTs are stateless; no token blacklist/rotation-reuse store | Test logout/password change/refresh replay; document observed lifetime and obtain security sign-off |
| Notifications | Local device scheduling, not server push; web delivery is not a supported native-notification assumption | Use real Android devices; test schedule fetch ordering, user scoping, permission denial and cancellation |
| Timezones | Notification implementation initializes timezone data but does not resolve the device zone into `tz.local` | Execute timezone/DST cases; do not certify reminders from UTC-only tests |
| Polling and refresh | Chat/data are loaded/refreshed by client; no WebSocket guarantee | Check supported refresh behavior; do not promise immediate real-time synchronization |
| Scheduling remainder modes | Cycle/truncation paths exist; extend-last and round-robin behavior require careful verification | Specify lead-approved desired allocations before running; report preview/actual and UI-description mismatches |
| Suggestion confirmation | Suggestion progression advances W per week, while independent scheduling advances N×W; custom steps fall back on confirmation | Preview must match saved assignments; a mismatch is a defect, not an acceptable difference |
| Concurrency | Duplicate checks are application queries, without an assignment-unit uniqueness constraint | Concurrent requests must be tested against PostgreSQL; duplicates are defects |
| Account-local preferences | Reading/bookmark/settings persistence is local, not guaranteed account-separated or cloud-synchronized | Test sign-out/account switching; flag privacy leakage and document intended policy |
| Content quality | Some extraction boundaries/OCR remain approximate; beta languages may contain garbled text | Compare with permitted source material; flag missing/duplicated text rather than declaring content complete |
| Cascades | Relationships and database foreign keys differ across SQLite/PostgreSQL | Verify cleanup on PostgreSQL, including messages, highlights and notification schedules; do not infer from SQLite tests |

## Permissions matrix

Validate both visibility in the UI and direct API rejection. Unauthorized changes must leave database state unchanged.

| Action in G1 | Guest | X | M1 | L | A |
|---|---|---|---|---|---|
| Read bundled content/media/public events | Yes | Yes | Yes | Yes | Yes |
| Create a group / join with valid code | Login required | Yes | Yes | Yes | Yes |
| Read G1 members, assignments, messages, highlights and reminder settings | No | No | Yes | Yes | Yes |
| Manual/auto assign; suggestions; advance week; delete assignments | No | No | No | Yes | Yes |
| Add/search users; remove ordinary members | No | No | No | Yes | Yes |
| Remove a group lead | No | No | No | No | Yes |
| Remove self/admin through member removal | No | No | No | No | No |
| Update group settings / change roles / delete group | No | No | No | No | Yes |
| Leave group | No | No | Yes | Yes | No; transfer/demote through another admin or delete first |
| Update assignment status | No | No | Own only | Own only | Own only |
| Send messages/highlights | No | No | Yes | Yes | Yes |
| Delete message/highlight | No | No | Own only | Any in group | Any in group |
| Configure reading reminder settings | No | No | No | Yes | Yes |
| Delete own account | No | Own | Own | Own | Blocked while admin of any group |

## Test-case catalogue

Columns: **ID**, **priority/layer**, **scenario and steps**, **expected result**. Each expected result is an assertion, not an execution claim.

### 1. Installation, launch, navigation and dashboard

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| NAV-01 | P0 UI | Fresh install/cleared browser storage; open app as Guest. | Home loads without login requirement, crash or indefinite spinner; public features are reachable. |
| NAV-02 | P1 UI | Start again with valid saved session; cold and warm launches. | Correct authenticated state/profile restores without a login flash or navigation reset. |
| NAV-03 | P0 UI/API | As Guest open Groups/Profile and their deep links. | Client redirects to login; direct private API requests are rejected. |
| NAV-04 | P1 UI | As Guest open reader, audio, live, events, daily programme and FAQ. | Public routes open without forced authentication. |
| NAV-05 | P1 UI | Login, then navigate directly to login/signup/phone-login. | Authenticated user is redirected to home; no redundant auth form. |
| NAV-06 | P1 UI | Switch all bottom tabs repeatedly; back/forward and Android back. | Selected tab/content stays consistent; no unexpected app exit or duplicate route stack. |
| NAV-07 | P1 UI | Refresh a web chapter/group deep link; open in a new tab. | Hosting serves the app route; auth gating is correct; no blank page or loss of requested public chapter. |
| NAV-08 | P1 UI | Use invalid chapter text/number, unknown route and nonexistent group. | Controlled not-found/error UI; no unhandled exception or unauthorized data. |
| NAV-09 | P1 UI | Submit a failing request from a nested page. | Loading/error auth-state changes do not recreate router and lose the page unexpectedly. |
| NAV-10 | P1 E2E | Compare dashboard counts before/after join, assign, completion and removal; refresh. | Counts reflect their documented local/server sources; no inflated totals or another user's data. |
| NAV-11 | P2 UI | Check quotes, quick actions, empty/new-user dashboard and long names. | Readable empty state, valid actions and no clipping. |
| NAV-12 | P1 UI | Open every modal and cancel using back, close, scrim or explicit cancel where allowed. | No accidental writes; focus and parent state recover. |

### 2. Email authentication, session and social sign-in

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| AUTH-01 | P0 E2E | Register unique email, valid name, 8-character password and matching confirmation. | One account created; profile and tokens returned; app enters authenticated flow. |
| AUTH-02 | P1 UI/API | Register with blank/whitespace name; boundary names and non-Latin text. | Blank rejected; Unicode retained; UI/API boundaries enforced independently without crash. |
| AUTH-03 | P1 UI/API | Use blank, malformed, missing-domain and overlong email; mixed-case valid email. | Invalid input rejected; valid email normalization consistent; no duplicate case-variant account. |
| AUTH-04 | P0 API/UI | Register duplicate email and duplicate normalized phone. | Controlled conflict response; no duplicate account or database 500. |
| AUTH-05 | P1 UI/API | Try passwords length 0, 7, 8, 128 and 129; spaces and Unicode. | 8/128 boundaries accepted as configured; out-of-range rejected; no undocumented complexity rule. |
| AUTH-06 | P1 UI | Mismatching/empty confirm password; toggle visibility; paste input. | Mismatch blocks submit; visibility affects only display; password remains unchanged. |
| AUTH-07 | P0 E2E | Log in with correct email/password, including mixed-case email. | Correct account/profile restored; no password returned or logged by client. |
| AUTH-08 | P0 API/UI | Wrong password and nonexistent email. | Same generic credential failure; no authenticated session and no account enumeration via distinct detail. |
| AUTH-09 | P1 UI | Double-tap registration/login, navigate away during submission. | Submit is disabled while pending; no duplicate user, state-after-dispose error or stray redirect. |
| AUTH-10 | P0 API | Make 10 failed login attempts for one email; try another within 15 minutes and after expiry. | Threshold response is 429; expiry permits attempts again; repeat on multiple workers and document limitation. |
| AUTH-11 | P1 E2E | Login/register while offline, timeout and server 500; retry after recovery. | Useful recoverable error; no false login, loss of form or infinite spinner. |
| AUTH-12 | P0 API | Use missing/malformed/expired/tampered access JWT and refresh JWT as access. | Protected API rejects; no private data or write; valid access token still works. |
| AUTH-13 | P0 E2E | Expire access token with valid refresh token; load profile/groups. | Client refreshes and retries original call with new access token, including `/auth/me`. |
| AUTH-14 | P0 E2E | Expire/revoke-by-deletion refresh token; simulate refresh 401. | Session expires cleanly; protected pages return to login; no retry loop. |
| AUTH-15 | P0 UI | Logout; cancel confirmation first, then confirm; restart app. | Cancel keeps session; confirm clears auth storage and group reminders; protected pages unavailable. |
| AUTH-16 | P1 API | Refresh with access token, invalid type, missing subject, expired and malformed tokens. | 401/validation response as appropriate; no new tokens. |
| AUTH-17 | P0 API | Replay old refresh token and retained access token after logout/password change. | Record observed stateless-token validity; lack of required revocation is a security finding, not a claimed pass. |
| AUTH-18 | P1 E2E | Trigger concurrent 401 requests and a failing refresh. | No infinite refresh recursion, multiple spurious session-expired messages or cross-user token overwrite. |
| AUTH-19 | P1 UI/API | Start Google sign-in; cancel provider; submit invalid provider/token directly. | Cancellation harmless; invalid provider rejected; current unconfigured Google route returns controlled 501 without account/tokens. |
| AUTH-20 | P1 UI/API | Start Apple sign-in/cancel; test backend with Apple provider. | Unsupported paths handled clearly; current backend extraction failure is controlled 400; successful E2E marked Blocked. |
| AUTH-21 | P1 UI | Inspect forgot-password/help affordances. | No claim of a working reset flow where none exists; recovery guidance honest. |
| AUTH-22 | P0 E2E | Account A logout then M1 login on same installation and separate tabs. | No A profile, assignments, tokens or notifications exposed to M1; account-local preference leakage reported. |

### 3. Phone and OTP authentication

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| OTP-01 | P1 API/UI | Submit valid international number; include spaces, hyphens and parentheses. | Accepted forms normalize consistently; six-digit OTP fixture created with 10-minute expiry. |
| OTP-02 | P1 API/UI | Blank/too-short/too-long number, leading zero, alphabetic input and invalid prefix. | Validation error before account creation; no uncontrolled 500. |
| OTP-03 | P0 API/E2E | Verify current OTP for existing P. | Logs into the same account; OTP becomes used; no duplicate P. |
| OTP-04 | P0 E2E | New phone: verify without name, then provide valid name using same OTP. | Initial 404 requests name without consuming OTP; retry creates one phone account. |
| OTP-05 | P0 API | Wrong OTP, another phone's OTP, already-used OTP and expired OTP. | 401; no account/token issued; correct phone/OTP remains scoped. |
| OTP-06 | P1 UI/API | OTP length 3/4/6/8/9, alphabetic and whitespace inputs. | UI digit/length validation enforced; server rejects invalid verification; schema discrepancy captured. |
| OTP-07 | P0 API | Five failed verification attempts, then sixth within 10 minutes. | Verification throttled with 429; does not bypass through alternate formatting of same number. |
| OTP-08 | P1 API/UI | Resend OTP; try old/new OTP; resend five times and request sixth/hour. | Prior unused OTP invalidated, newest accepted; rate limit and UI resend state correct. |
| OTP-09 | P1 UI | Back/cancel between number/OTP/name steps; network failure and retry. | No unintended account; number and step recovery understandable. |
| OTP-10 | P0 OPS | Exercise actual SMS delivery only with configured sender; inspect production logging. | Real delivery must be independently proven; current sender absent => Blocked; plaintext production OTP logging is unacceptable. |

### 4. Profile, preferences and account deletion

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| PROFILE-01 | P1 E2E | Open/edit profile; update name, email/phone where offered; restart. | Own changes persist; profile and chat author display refresh appropriately. |
| PROFILE-02 | P1 API/UI | Empty PATCH, blank name, invalid email/phone, duplicate identifier and long avatar URL. | 400/422 as appropriate; previous profile intact. |
| PROFILE-03 | P0 API | Clear primary email for email account or phone for phone account. | Reject login-identifier removal; account remains usable. |
| PROFILE-04 | P0 E2E | Change email-account password with correct current password. | New password works; old password fails; app handles returned result; assess old JWT validity separately. |
| PROFILE-05 | P1 API/UI | Wrong current password; new password boundaries/mismatch; phone account password change. | Wrong credential rejected; 8–128 enforced; phone account cannot use email password-change API. |
| PROFILE-06 | P1 UI | Toggle dark mode; traverse all screens and restart. | Preference persists; reader and app surfaces/text remain readable; no light-only illegible controls. |
| PROFILE-07 | P1 UI | Open About/version/help/FAQ links. | Display matches build; links valid; no placeholder support claim. |
| PROFILE-08 | P0 E2E | As A attempt account deletion while admin; cancel deletion; resolve admin role and retry. | Admin deletion blocked with actionable message; cancel no-op; eligible deletion succeeds. |
| PROFILE-09 | P0 API | Inspect deleted account and use retained access/refresh tokens. | Personal fields scrubbed, memberships/assignments removed; old tokens denied; references show Deleted user. |
| PROFILE-10 | P0 E2E | Delete eligible account while media/reminders active; reopen client. | Client signed out; private data/reminders cleared as policy requires; no crash from preserved messages/highlights. |

### 5. Groups and membership

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| GRP-01 | P0 E2E | Create chapter-wise G1 with defaults. | One group; A auto-added as admin; six-character unique invite code; correct initial week/settings. |
| GRP-02 | P1 UI/API | Create with blank name; UI lengths 1/2/80/81; API 1/255/256; description 1000/1001. | Respective boundaries enforced; validation mismatch documented; Unicode name preserved. |
| GRP-03 | P1 API/UI | Create Saptah group and invalid mode; settings chapters/week 0/1/53/54 and start 0/1/53/54. | Valid configured modes/ranges accepted; invalid rejected; do not infer an unimplemented seven-day algorithm. |
| GRP-04 | P1 E2E | List no groups, one group and many groups; pull refresh after mutation. | Correct own memberships only; clear empty state and stable cards/counts. |
| GRP-05 | P0 E2E | M1 joins G1 using invite; try lowercase and surrounding whitespace. | API normalizes case/trim; one membership created; count and role become correct. |
| GRP-06 | P1 API/UI | Invalid/nonexistent code; lengths 3/4/8/9/20/21; rejoin same group. | Not-found/validation/duplicate responses controlled; no double membership; UI/API length mismatch surfaced. |
| GRP-07 | P0 API | X/Guest request G1 detail, assignments and member data by known UUID. | Denied without private data, including valid UUID guess. |
| GRP-08 | P1 UI | Copy/share invite; cancel share; device/browser without share support. | Correct group/code shared, clipboard feedback correct, graceful fallback and no secret token sharing. |
| GRP-09 | P1 E2E | A updates chapters/week, start chapter and current week; reload another device. | Values persist, expected scheduling uses them; existing saved assignments not silently rewritten. |
| GRP-10 | P0 API/UI | L/M1 try admin-only settings/roles/delete through UI and direct API. | 403 and no mutation; UI hides/disables or explains restricted actions; misleading lead controls reported. |
| GRP-11 | P1 API/UI | Promote member to lead/admin, demote another authorized target; invalid role/nonmember/self-demotion. | Admin-only rules enforced; self-admin demotion blocked; active permissions refresh after role change. |
| GRP-12 | P1 E2E | A/L search and add registered users; short query, name/email/phone match, >20 matches. | Authorized lookup only, existing members excluded, result cap 20 and contact masking enforced. |
| GRP-13 | P0 API | M1/X attempt search/add; add unknown/already-member user. | Permission/error response; no PII leak, duplicates or ghost membership. |
| GRP-14 | P0 E2E | A/L removes M1 with assignments; inspect assignments/progress and refresh M1. | Correct member removed; related assignments cleaned; M1 loses private group access. |
| GRP-15 | P0 API | Remove self/admin; L removes L-type target; A removes lead. | Self/admin removal blocked; lead cannot remove lead; admin may remove another lead. |
| GRP-16 | P0 E2E | M1/L leaves group; A attempts leave; cancel leave confirmation. | Eligible leave works; admin leave blocked; cancellation no-op; verify cleanup/reminders and report stale own assignments. |
| GRP-17 | P0 E2E/API | A deletes group populated with assignments/progress/chat/highlights/reminder schedule. | Group deletion follows policy without FK 500; dependencies cleaned or retained only under explicit policy; all former members lose access. |
| GRP-18 | P1 E2E | Simultaneous join/add/remove and group deletion from two devices. | Consistent membership/counts; no duplicate, stale privileges, crash or partially deleted group. |

### 6. Manual group reading assignments

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| MAN-01 | P0 E2E | A/L opens Schedule → Manual Assign; select M1, week and one chapter; save. | One assignment for M1/selected week with not-started progress; parent switches/refreshes selected week. |
| MAN-02 | P1 UI | Open Manual Assign in empty and populated schedules; M1/X tries access. | Lead/admin entry available in both states; ordinary members cannot assign; direct API still authoritative. |
| MAN-03 | P0 E2E | Select nonconsecutive chapters 1, 8 and 20; save to M1/week 3. | Exactly three selected readings saved; no intervening chapters auto-added. |
| MAN-04 | P0 E2E | Assign each combined range from chooser. | 16–17, 18–19, 43–44 and 51–53 listed once each; one record and one status per selected range. |
| MAN-05 | P0 API | Send ID for chapter 17/19/44/52/53 directly. | Canonical IDs resolve to 16/18/43/51; range label/end correct. |
| MAN-06 | P0 E2E/API | Use fixture IDs ≠ numbers; assign chapter 16. | Client sends real server ID; stored number is 16, not a chapter accidentally selected by number-as-ID. |
| MAN-07 | P1 UI/API | Marathi server index; older English-only index; no index and network failure. | Marathi preferred; empty Marathi falls back to English; absent data shows retry, no guessed IDs. |
| MAN-08 | P0 E2E/API | Same M1/group/week already has chapter 16 or legacy 17; select range/repost. | Chooser disables range; backend rejects duplicate range for that week with no extra row. |
| MAN-09 | P0 E2E | Assign same range to M2, another group, and M1 in a later week. | Each legitimate combination allowed; no across-week false duplicate rejection. |
| MAN-10 | P1 UI | Change member/week after selecting chapters. | Selection clears; already-assigned indicators recompute for new context. |
| MAN-11 | P1 UI/API | Week blank, 0, negative, nonnumeric and large positive; no member/no chapter. | UI/API enforce week ≥1; save disabled without required choices; large number/date overflow handled rather than server 500. |
| MAN-12 | P1 UI | Search by chapter number, range and title; unmatched query; clear query. | Correct choices shown; selection survives filtering; no-match state recoverable. |
| MAN-13 | P0 API | Assign nonexistent chapter, nonmember, removed user or deleted group. | 404/400/403 as appropriate; no orphan assignment or progress. |
| MAN-14 | P1 API | Selected week 5 when current week 3; omit date; then send explicit date. | Default Monday is reference Monday +2 weeks; explicit date preserved. |
| MAN-15 | P0 UI/E2E | Save several readings; fail second request; retry remaining selection. | Successful first save retained/unselected; failure shown; retry does not resubmit saved unit; no claim of atomic batch. |
| MAN-16 | P1 UI | Slow save, double tap, dismissal during save, retry loading. | Save lock prevents duplicate UI submissions; no post-dispose error; successful writes remain visible after reopening. |
| MAN-17 | P1 UI | Small screen, landscape, keyboard and large text while choosing member/week. | Form/chapters scroll, Save remains reachable; no overflow or hidden validation message. |
| MAN-18 | P0 API | Concurrent same-unit posts for M1/group/week in PostgreSQL. | At most one assignment/progress pair; race-created duplicates reported as defect. |

### 7. Combined chapters and content mapping

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| COM-01 | P0 E2E | One member, one reading/week, start 15, four weeks. | Sequence **15 → 16–17 → 18–19 → 20**, not 15/16/17/18. |
| COM-02 | P0 API/E2E | Parameterize starts 17, 19, 44, 52, 53. | Normalize to 16–17, 18–19, 43–44, 51–53, 51–53 respectively; progression moves past whole unit. |
| COM-03 | P0 DATA | Inspect every non-Marathi asset and Marathi originals. | Translation range metadata consistent for all four ranges; Marathi separate numbers 1–53; no false 50–53/52–53 range. |
| COM-04 | P0 E2E | Open assigned range in every selectable non-Marathi language. | Combined content loaded once, full range label shown, no duplication per original number. |
| COM-05 | P0 E2E | Open each group range in Marathi; inspect full body; open standalone book separately. | Group reader includes each original exactly once; standalone Marathi chapters remain separate. |
| COM-06 | P0 E2E | Complete Marathi/translated combined assignment. | One server progress record completes; all original numbers in the group unit marked locally; no skipped adhyaya. |
| COM-07 | P1 E2E | Prev/next around 15/16–17/18–19/20 and 42/43–44/45. | Translated reader navigation neither repeats range nor skips next entry; Marathi standalone navigation remains sequential. |
| COM-08 | P0 E2E | Assign/read chapter 50 in a translation lacking it. | Marathi fallback supplies 50; it is not silently dropped or merged into final range for scheduling. |
| COM-09 | P1 UI | Inspect cards, suggestions, reminders, completion message and next-unscheduled start controls. | Labels carry full ranges consistently; controls never select an interior as a separate unit. |
| COM-10 | P0 E2E/API | Load legacy saved 16/week1 +17/week2 assignments; rerun/new schedule. | Existing records are not silently rewritten; duplicates/legacy state disclosed; regeneration procedure preserves completed-history decision. |

### 8. Automatic schedules, suggestions and week management

Use ordered members M0=A, M1 and M2; W is readings/member/week; unit positions include combined ranges as one. For start position s, zero-based week k and member i: independent `s+kNW+iW`; rotating `s+(k+i)W`; dense `s+kW+i`; synchronized `s+kW`.

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| SCH-01 | P0 E2E/API | Independent: N=3, W=2, start1, two weeks. | Week1 allocations 1/2, 3/4, 5/6; week2 7/8, 9/10, 11/12; no unintended overlap. |
| SCH-02 | P0 API/E2E | Rotating-window same fixture, two weeks. | Week1 1/2, 3/4, 5/6; week2 3/4, 5/6, 7/8; intended cross-week overlap only. |
| SCH-03 | P0 API/E2E | Dense-window same fixture. | Week1 1/2, 2/3, 3/4; week2 3/4, 4/5, 5/6; correct user/week assignment identities. |
| SCH-04 | P0 API/E2E | Synchronized same fixture. | Everyone reads 1/2 week1 and 3/4 week2; no global deduplication that removes others' readings. |
| SCH-05 | P0 API | Repeat four modes with start15, W=1/2/3 and N=1/2/3. | Apply formulas to reading-unit positions, not raw chapter numbers; all ranges remain atomic. |
| SCH-06 | P1 API/UI | Weeks-ahead 0/1/12/13; invalid mode/remainder; start0 and past book end. | Defined schema boundaries enforced; out-of-book input reported as remainder or controlled error, never crash. |
| SCH-07 | P1 E2E | Members with identical/near-identical join times; member added between scheduling runs. | Stable documented join order; no arbitrary reassignment of saved history. |
| SCH-08 | P0 API | Cycle from chapter53 with W=2, one week. | Readings **51–53 and 1**; no standalone 52/53 and correct wrap after final unit. |
| SCH-09 | P0 API | W=2, start49, two weeks, truncate/manual. | Available units 49,50,51–53 assigned; extra unit positions reported; no nonexistent chapter write. |
| SCH-10 | P1 E2E/API | Exercise manual, truncate, extend-last and round-robin remainder options against approved expected allocation. | Actual outcomes and UI descriptions agree; unsupported/no-op behavior reported explicitly. |
| SCH-11 | P0 API/E2E | Repeat identical schedule request; include manual and legacy interior assignments. | Existing same-user/week unit skipped; no duplicate assignment; other users remain independently assignable. |
| SCH-12 | P0 API | W larger than unit count with cycle; repeat same unit within a week. | Same user/week not duplicated; returned created/remainder information explains reduced count. |
| SCH-13 | P1 UI | Auto-fill next unscheduled start after a combined range and after book end. | Next whole unit selected; no repeated interior; book-complete state not a misleading phantom chapter. |
| SCH-14 | P0 E2E/API | Suggest hints 1 and3 for W=2; 1 and2; 1 and4. | Non-overlapping/dense/custom detection and step accurate in unit positions; preview clearly labels manual/computed slots. |
| SCH-15 | P0 API | Suggest hints16 and18 with W=1; hints inside ranges; nonconsecutive positions, reversed/zero step. | Normalization gives unit step1 for16/18; malformed/ambiguous input handled; no negative/phantom chapters. |
| SCH-16 | P1 API/UI | Too few hints, nonexistent positions, one-member group, duplicate positions. | Validation/help prevents meaningless pattern; any accepted ambiguous extrapolation documented as defect risk. |
| SCH-17 | P0 E2E | Compare every suggestion cell with confirmed schedule for N>1, ≥2 weeks; include custom steps. | Saved user/week/unit grid equals approved preview; known advance/fallback mismatch must fail until resolved. |
| SCH-18 | P1 API | Suggestions only, no confirmation. | No assignments/progress created; all expected metadata/range labels returned. |
| SCH-19 | P0 E2E | A/L advances current week; navigate previous/future weeks. | Current week increments once, filters correct; saved assignments not moved; M1 cannot advance through API. |
| SCH-20 | P0 API/OPS | Concurrent schedules/advance-week requests and large N×W×weeks dataset. | No duplicate units/lost week update or partial transaction; bounded response time/memory measured on PostgreSQL. |

### 9. Reader, bookmarks, local history and content updates

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| READ-01 | P0 UI/DATA | Open list and first/middle/final chapters for each selectable language. | Correct number/range and body load; no missing asset, empty content or endless loading. |
| READ-02 | P1 UI | Search by number/range/title/content supported by the screen; empty and no-match search. | Only supported search semantics advertised; clear query restores list; results navigate correctly. |
| READ-03 | P1 UI | Increase/decrease font to both limits; restart; render verse/subheadings/long paragraphs. | Limits enforced; setting retained; readable layout without clipping/missing text. |
| READ-04 | P1 UI | Bookmark/unbookmark singleton and combined chapter; reload/restart. | Correct chapter identity retained; no duplicate/wrong-language bookmark marker. |
| READ-05 | P1 UI | Read partway, leave/reopen and cold restart; short unscrollable chapter. | Resume works after content is laid out; progress bounded; no scroll division error or false completion. |
| READ-06 | P0 UI | Open bundled reader in airplane/offline mode after install. | All bundled chapters readable; server update failure does not replace content or require login. |
| READ-07 | P1 UI/API | Invalid chapter number, missing translated adhyaya and no Marathi fallback. | Documented Marathi fallback used when available; otherwise clear not-found state. |
| READ-08 | P0 DATA/API | Server version older/equal/newer; malformed/empty/partial book update. | Older/equal ignored; full valid newer book may update cache; partial copy never replaces full bundled book. |
| READ-09 | P1 UI | Switch languages rapidly during content/update fetch; return to cached language. | Correct per-language body/cache; stale responses do not substitute another language. |
| READ-10 | P1 UI | Complete one local reading; check streak/history/dashboard; cross midnight and reinstall. | Daily record not repeatedly inflated; local-only persistence/clear-on-reinstall behavior documented. |
| READ-11 | P0 UI | A reads/bookmarks then logs out; M1 logs in on same device. | Account-scope policy tested; any unauthorized exposure of prior personal history reported. |
| READ-12 | P1 UI | Reader prev/next at book boundaries; repeatedly move through full book. | No chapter0/>53, cyclic duplicate translation range or broken back stack. |
| READ-13 | P1 UI | Reader opened by public deep link versus group card versus refreshed group deep link. | Public reading does not falsely update assignment; group context retained or clearly absent after refresh. |
| READ-14 | P0 DATA | Compare all chapters with permitted source, especially translated merged ranges and final chapters. | No missing, duplicated, out-of-order or unrelated passages; verified issues recorded per language/chapter. |

### 10. Assignment progress and reading completion

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| PROG-01 | P0 E2E | M1 changes own reading through all three statuses; reload M2's group schedule. | One progress record updated with timestamp; group sees saved status after refresh. |
| PROG-02 | P0 API | A/L/M2 tries to update M1's assignment. | 403 even for admins/leads; no progress mutation. |
| PROG-03 | P1 API | Invalid status, nonexistent assignment, missing progress row, outsider read. | Validation/404/403 correct; authorized update can create missing progress record; no duplicate progress. |
| PROG-04 | P1 UI | Scroll assigned reading to <95% then ≥95%; keep scrolling. | Completion prompt appears once at threshold; no duplicate sheets. |
| PROG-05 | P0 E2E | Choose Completed in prompt. | Server complete, local range history updated, completion chat message correct, reminders canceled as supported. |
| PROG-06 | P1 UI | Choose Later, dismiss prompt, or read standalone chapter. | No false server completion or automatic group chat post. |
| PROG-07 | P0 E2E | Progress succeeds but local persistence/chat fails; reopen and retry. | Saved status not lost; no misleading full-success claim; duplicate completion messages/retries checked. |
| PROG-08 | P0 E2E | Delete assigned reading with progress/reminders; assignment open on another device. | Progress removed, local reminders canceled, stale UI recovers; unauthorized deletion rejected. |
| PROG-09 | P1 API/E2E | Mark completed then revert to not-started; inspect reminders and labels. | Permitted API transition is represented correctly; notification rescheduling aligns with new state. |
| PROG-10 | P0 E2E | Member removed/leaves while assigned reader stays open; submit completion. | No unauthorized continued group activity; membership/ownership policy checked and stale writes reported. |

### 11. Group chat and highlighted comments

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| CHAT-01 | P0 E2E | M1 sends message; M2 refreshes; Unicode/emoji/multiline text. | One message with correct author/time/body; group isolation maintained. |
| CHAT-02 | P1 UI/API | Message blank/whitespace, lengths1/2000/2001; repeated send while loading. | Trim/validation applied; blank and overlong rejected; no duplicate accidental sends. |
| CHAT-03 | P0 API | X sends/reads/deletes G1 messages; M1 attempts another member's deletion. | Permission denied; message data unchanged. |
| CHAT-04 | P1 API/UI | Author deletes own message; A/L moderates; nonexistent ID/wrong-group ID. | Allowed deletion removes only target; wrong group never deletes another group's message. |
| CHAT-05 | P1 API | Request limits0/1/100/101 and cursor pagination; same timestamps, invalid/cross-group cursor. | Bounds enforced; stable pagination and group-scoped cursor behavior; no missing/duplicated/privacy-leaking results. |
| CHAT-06 | P1 E2E | Large history, refresh/scroll, offline post and reconnect. | Readable ordering and scrolling; controlled failure/retry, no unsupported instant-delivery claim. |
| CHAT-07 | P0 API/E2E | Post highlight with server chapter ID, text, paragraph index and comment. | Correct group/chapter/author stored and displayed; source text/comment preserved. |
| CHAT-08 | P1 API | Highlight text0/500/501; comment0/2000/2001; index−1/0; unknown chapter. | 422/404 as appropriate; whitespace-only rejected and no orphan highlight. |
| CHAT-09 | P0 API/UI | Read chapter-filtered highlights; outsider access; delete by owner/moderator/nonowner. | Proper filter/permissions; unrelated group's entries never exposed or deleted. |
| CHAT-10 | P1 UI/E2E | Open highlight location if UI supports it; switch language/combined chapter. | Chapter identity/anchor meaningful; unsupported creation/navigation is not advertised as working. |
| CHAT-11 | P0 E2E | Delete sender account while retained chat/highlights exist. | References remain valid with anonymized name; no original PII or client crash. |
| CHAT-12 | P0 UI/API | Submit HTML/script-like text, links, quotes and SQL-like text as message/comment. | Rendered as inert text; no script execution, SQL effect or unsafe URL auto-execution. |

### 12. Daily verses and group reading reminders

Use a real native device and inspect pending notifications as well as delivered notifications. Web plugin errors/unsupported delivery must not break core reading.

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| NOTIF-01 | P1 UI | Enable daily verse; grant permission; set time; restart app. | One daily notification at chosen device-local time; preference retained. |
| NOTIF-02 | P1 UI | Deny permission, revoke in OS, re-enable and change time. | No crash or false enabled-success; guidance and repermission behavior clear; old time canceled. |
| NOTIF-03 | P1 UI | Disable daily verse; observe next day; check daily verse over several days. | Disabled notification canceled; claimed daily verse rotation actually occurs or documented discrepancy is reported. |
| NOTIF-04 | P1 API/E2E | A/L saves group reminder day/hour/minute and escalation; M1 fetches. | One server schedule persisted/updated with configured values; M1 can read but cannot write. |
| NOTIF-05 | P1 API | Days−1/0/6/7; hours−1/0/23/24; minutes−1/0/59/60; missing schedule/group. | Boundaries enforced; controlled404 for no settings; no notification-related page failure. |
| NOTIF-06 | P0 E2E | M1 opens G1 schedule; compare queued reminders for M1/M2. | Only current device user's assignments scheduled, never another member's private reading reminders. |
| NOTIF-07 | P1 E2E | Initial reminder plus escalation72/48/24/12/6/2 hours before future deadline. | Future configured notifications queued once; past times skipped; full combined label where applicable. |
| NOTIF-08 | P1 E2E | Disable escalation; deadlines past; reminder after deadline; open past/future week. | Defined scheduling behavior; no stale/past spam; illogical reminder/deadline configuration reported for product decision. |
| NOTIF-09 | P0 E2E | Complete/delete assignment, logout, leave group and delete account. | Relevant queued group reminders canceled; no reminder for unauthorized/completed work; daily preference handled separately. |
| NOTIF-10 | P1 E2E | Change settings after reminders queued; repeat page load and cold restart. | Existing reminders replaced, not duplicated; IDs remain cancelable across process restart. |
| NOTIF-11 | P1 E2E | Schedule fetch slower/faster than assignments; first open without settings then settings created. | No load-order-dependent lost reminder; device schedules after both required datasets arrive. |
| NOTIF-12 | P0 E2E | Asia/Kolkata versus UTC; DST forward/back; midnight/Monday boundaries; change device timezone. | Delivery matches intended local week/time; UTC-local and DST defects recorded with exact clock evidence. |
| NOTIF-13 | P1 UI/OPS | Android idle/battery saver/reboot; OS notification limit; app force-stop. | Platform behavior measured/disclosed; no promise of exact delivery under inexact scheduling or force-stop restrictions. |
| NOTIF-14 | P1 UI | Open notification preferences/group schedule on web or unsupported desktop. | Graceful unsupported state; no core feature crash or misleading push-notification guarantee. |

### 13. Audio playback, download and media switching

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| MEDIA-01 | P1 UI/E2E | Open aarti and chapter audio; play, pause, resume and stop an available track. | Correct track plays; controls/state match; no simultaneous unintended players. |
| MEDIA-02 | P1 DATA/UI | Inspect five aarti groups and all offered chapter-audio languages/tracks. | Metadata/files/labels correspond; missing languages do not show a misleading playable icon. |
| MEDIA-03 | P0 E2E | Open reader audio for every combined unit and interior number supported by catalog. | Track covers the requested original number/range; no off-by-one or wrong-language audio. |
| MEDIA-04 | P1 UI | Seek, change supported speed/control settings and skip near start/end. | Duration/position valid; supported controls work; no negative/oversized seek. |
| MEDIA-05 | P1 UI | Native first play downloads; cached second play offline. | Progress displayed; downloaded file reused, valid audio plays without network. |
| MEDIA-06 | P1 UI | Web release play after user gesture; inspect manual web plugin registration. | Streaming works without filesystem access or unregistered-player error; autoplay restrictions handled. |
| MEDIA-07 | P1 E2E | Media404/timeout/redirect/offline mid-download/corrupt partial file; retry. | Recoverable error; partial file not treated as complete; loading state ends. |
| MEDIA-08 | P1 UI | Native low disk space, download cancel if offered, app kill during download. | No crash or unusable cache; interrupted file retried or cleaned safely. |
| MEDIA-09 | P1 UI | Switch track/language, open reader audio while hub audio playing, close mini-player. | Previous playback handled consistently; current metadata accurate; resources released. |
| MEDIA-10 | P1 UI | Background/foreground, screen lock, Bluetooth/headphone disconnect and interruptions. | Behavior matches platform/product policy; no unexpected loud playback or lost controls. |
| MEDIA-11 | P1 UI | Reach end of track; replay; rapidly alternate play/pause and route changes. | Completion state recoverable; no player exception, leaked session or duplicate download. |
| MEDIA-12 | P1 OPS | External release/source URLs unavailable or changed; limited bandwidth. | App stays usable; no guaranteed offline media before successful download; actionable unavailable state. |

### 14. Live Darshan, events, daily programme and FAQ

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| LIVE-01 | P1 E2E | Open live stream with upstream available on Android and release web. | Current HLS URL retrieved; supported player loads picture/sound after required gesture. |
| LIVE-02 | P1 API/UI | Upstream timeout/HTTP error or missing `newurl` fixture. | Backend502 with clear error; client offers recovery and no endless spinner. |
| LIVE-03 | P1 E2E | Expired stream URL, token renewal, network change and repeated refresh. | Fresh URL fetched; supported recovery resumes playback without stale token loop. |
| LIVE-04 | P1 UI | Fullscreen, orientation, mute/unmute, back navigation and background. | Correct aspect ratio, control state and lifecycle; video stops/releases as intended. |
| LIVE-05 | P1 UI | Browser/Electron without AAC codec; inspect fallback if present. | Controlled video-only fallback or meaningful failure; no false claim of full audio support. |
| LIVE-06 | P1 OPS | HTTPS app with API/player media origins; browser CORS/CSP and WebView limitations. | No mixed-content or origin failure in target hosting; desktop fallback verified where configured. |
| INFO-01 | P1 UI/API | Load events with cached data, empty database, slow refresh and upstream failure. | Clear loading/empty/error state; last valid events remain usable; dates/order correct. |
| INFO-02 | P1 API/DATA | Scrape permitted festival HTML fixture; malformed/date-variant/duplicate entries. | Valid data parsed without duplicates/data corruption; source URL/date text preserved. |
| INFO-03 | P1 OPS | Daily scheduled scrape/startup scrape; restart and multiple workers. | No duplicate jobs/writes or uncontrolled external requests; failures logged without blocking app startup. |
| INFO-04 | P2 UI | Open festival links and daily programme; cancel external navigation. | Valid official links; schedule readable, properly localized or clear fallback. |
| INFO-05 | P1 UI | FAQ search/categories/expand-collapse supported controls; all languages and offline. | Questions/answers render; unsupported controls not assumed; no clipped answers or broken help links. |
| INFO-06 | P1 UI | Guest accesses all information screens; backend/media unavailable. | Public accessibility remains; bundled information not needlessly blocked. |
| INFO-07 | P1 API | Force `/festivals/refresh` as Guest and authenticated ordinary user; repeated requests. | Guest rejected; current route allows any authenticated user despite admin/internal comment; scope/throttle requirement reviewed and upstream abuse risk recorded. |

### 15. Language, scripture quality and localization

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| LANG-01 | P1 UI/DATA | Verify available codes en,mr,te,hi,ta,bn,sd,es,gu,ml,or,kok,ne,pa,kn,de,fr. | All17 selectable; ur asset exists but Urdu not selectable; beta markings align with source flags. |
| LANG-02 | P1 UI | Fresh install in supported device locale and unsupported locale. | Supported available locale selected; unsupported/disabled defaults to English. |
| LANG-03 | P0 UI | Change app language, then choose different reader language; restart. | App change syncs both initially; later reader-only change independent; both preferences retained. |
| LANG-04 | P1 UI | Save/cancel language chooser; rapid changes while reader/list open. | Cancel no-op; saved selections apply without stale list or mixed-language body. |
| LANG-05 | P1 UI | Traverse every screen in each selectable UI language. | Correct labels where translated; understandable fallback; hardcoded/untranslated text tracked instead of assumed complete localization. |
| LANG-06 | P0 DATA/UI | Native scripts/diacritics/ligatures, long German/French/Spanish text, beta OCR samples. | No replacement boxes/garbled encoding; content review identifies omissions and OCR defects. |
| LANG-07 | P1 UI | Legacy stored Urdu preference and unknown language code. | Controlled legacy/fallback behavior; no crash or silently inaccessible settings. |
| LANG-08 | P1 DATA | Check headings, subheadings, first/last passage, duplicated page numbers and boundaries in all assets. | Correct chapter ownership/order; permitted-source comparison and reviewer evidence attached. |

### 16. Accessibility, usability and responsive layout

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| A11Y-01 | P1 UI | Android TalkBack/web screen reader through auth, chapters, group schedule and manual sheet. | Meaningful labels/order/state for buttons, errors, selected chapters and status; no inaccessible critical flow. |
| A11Y-02 | P1 UI | Keyboard-only web: tab, shift-tab, enter, space, escape and dropdowns/dialogs. | Visible focus, usable controls, no focus trap; focus returns after modal dismissal. |
| A11Y-03 | P1 UI | Text scaling100/150/200%, smallest target viewport, landscape/tablet. | No clipped core content, unreachable action or horizontal overflow; scrolling usable. |
| A11Y-04 | P1 UI | Measure light/dark contrast and status indicators. | Target WCAG2.2 AA where applicable; status not conveyed only by color. |
| A11Y-05 | P1 UI | Touch targets, icon tooltips, form error announcement and loading announcements. | Comfortable targets (platform guidance), clear purpose, errors associated with field and announced. |
| A11Y-06 | P1 UI | Large keyboard, autofill, password manager, virtual navigation bars and safe areas. | Fields/actions remain visible and usable; no accidental sensitive autofill exposure. |
| A11Y-07 | P2 UI | Reduced motion, high-contrast OS setting and screen rotation during modal/media. | No seizure-inducing flashes or disruptive animation; state retained or controlled recovery. |
| A11Y-08 | P1 UI | User cannot distinguish icons/colors; attempt main task from empty states. | Text guidance explains manual/automatic assignment and completion; destructive actions require confirmation. |

### 17. Security, privacy and API contract

All security testing must be authorized and restricted to the isolated test environment.

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| SEC-01 | P0 API | Run entire permissions matrix with Guest/X/M1/L/A for every protected route. | Backend enforcement correct regardless of client control visibility; no unauthorized disclosure/write. |
| SEC-02 | P0 API | Swap group/member/assignment/message/highlight UUIDs between G1/G2; guess valid IDs. | Object-level authorization and group scoping prevent IDOR. |
| SEC-03 | P0 API | Request own/other profile and search results; inspect responses/logs. | No password hashes, raw OTPs or tokens exposed beyond designated auth responses; contacts masked where intended. |
| SEC-04 | P0 OPS | Inspect release client storage, network capture and server logs. | Production HTTPS; tokens not in URLs/analytics; storage protection and log redaction independently verified. |
| SEC-05 | P0 API | JWT tampering/algorithm confusion, expired/deleted-user token and refresh replay tests. | Invalid tokens rejected; replay/revocation limitations explicitly assessed and approved. |
| SEC-06 | P1 API | Missing/extra fields, malformed JSON, wrong scalar types, large bodies, nulls and boundary integers. | Consistent validation without data corruption, debug traceback leak or resource exhaustion. |
| SEC-07 | P0 API | Reuse sessions after membership/role revocation; active reader/chat/manual modal left open. | Revoked privileges do not survive in new API operations; stale UI recoverable. |
| SEC-08 | P1 OPS/API | Untrusted web origin versus allowlisted origin; OPTIONS request and HTTPS deployment. | CORS policy restricts production clients as configured; browser access works only for approved origins. |
| SEC-09 | P1 API | Concurrent profile email/phone updates, assignment creates and account deletions. | Unique constraints/transactions fail safely; no500 disclosure, duplicate identity or orphan state. |
| SEC-10 | P0 OPS | Rate-limit across worker restart/multiple workers and identifiers/IP sources. | Process-local limits not overstated; production abuse-control requirements met or release blocked. |
| SEC-11 | P1 UI/API | Malicious input rendered in names, descriptions, chat/highlights/avatar links. | Text inert, external resources controlled; no XSS/injection or automatic sensitive navigation. |
| SEC-12 | P0 E2E/OPS | Logout/delete/share/export-like actions with notifications/cache/downloads present. | No personal data leaked to next user or share sheet; retention/deletion policy documented and verified. |

### 18. Offline behavior, resilience and performance

Set measured budgets with product/device owners before executing; there are no hardcoded unverified performance guarantees in this plan.

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| RES-01 | P0 UI | Offline cold/warm launch, chapters/bookmarks/settings and public information. | Bundled/local functions usable; network-only actions accurately unavailable; no false sync claim. |
| RES-02 | P1 E2E | Offline group create/join/manual/progress/chat; reconnect. | No unadvertised offline queue; failure clear; retry reconciles confirmed server writes. |
| RES-03 | P1 E2E | Server commits then connection drops before response; retry create/assign/message. | Duplicate-risk recovery tested; no silently repeated critical write; idempotency gaps recorded. |
| RES-04 | P1 UI | Switch Wi-Fi/mobile/offline repeatedly during content/audio/group load. | Loading ends; controls recover; no stale data presented as successfully refreshed. |
| RES-05 | P1 UI | Rapid navigation and app background/kill during async operation. | No state-after-dispose exceptions, leaked players or lost authoritative writes. |
| RES-06 | P1 OPS | Measure cold start, first reader load, large chapter scroll and language switch on low-end target. | Meets approved budget; measurements include device/build/network and percentiles. |
| RES-07 | P1 OPS/API | Large groups/assignments/chat history and12-week schedules; simultaneous users. | API response/DB query/resource use meet approved capacity; no unbounded N+1 regressions hidden by small fixtures. |
| RES-08 | P1 OPS | Long audio/live session and repeated language/group transitions. | No sustained memory growth, battery regression, audio session leak or UI jank beyond approved budget. |
| RES-09 | P1 OPS | Backend DB unavailable/restarts, external host slow/unavailable. | Requests fail within configured timeouts; no partial corrupt state; service recovers cleanly. |
| RES-10 | P1 UI | Corrupt/missing preference/cache values; storage full/permission failure. | Safe defaults and recoverable errors; no permanent launch crash or accidental account/session mix. |

### 19. Builds, deployment and release readiness

| ID | Priority / layer | Scenario and steps | Expected result |
|---|---|---|---|
| OPS-01 | P0 OPS | Start isolated API/database; health, OpenAPI and chapter index; restart. | Healthy startup; one index row per intended number; restart does not duplicate seed or lose PostgreSQL data. |
| OPS-02 | P0 OPS | DEBUG=false with default JWT secret, then valid configured secret. | Unsafe-default startup refused; secure config starts successfully; no secrets printed. |
| OPS-03 | P1 OPS | Verify environment precedence, CORS array parsing and API base URL per target. | Effective config matches deployment; Android localhost not mistaken for host machine; no hardcoded production fallback. |
| OPS-04 | P0 OPS | Fresh database/schema creation plus existing-version migration/backup rehearsal. | No schema drift or data loss; Alembic requirements reviewed; backup restored and app usable. |
| OPS-05 | P0 OPS | Android release install and web release hosting; repeat smoke pack. | Assets/routes/audio registration function in release; no debug-only behavior or missing bundled language. |
| OPS-06 | P1 OPS | HTTPS web deep-link hosting and API reachability from emulator/real device. | SPA route fallback and allowed origins configured; health/API/media reachable. |
| OPS-07 | P1 OPS | Fresh install versus upgrade with old preferences/legacy schedules/cached audio. | Compatible restore and honest regeneration guidance; no silent history loss or duplicate reminders. |
| OPS-08 | P1 OPS | Run backend/Flutter tests, analyzer and dependency/security scan. | Failures reviewed; warnings triaged; reported test counts reflect actual run, not old documentation. |
| OPS-09 | P0 OPS | Verify supported-platform, SMS/social-auth, notification and content-beta release statements. | Documentation/store claims match certified behavior; unsupported features disabled or clearly disclosed. |
| OPS-10 | P1 OPS | Verify test-fixture cleanup, telemetry/log redaction and rollback after release rehearsal. | No test accounts/data in production; rollback/restore tested with accountable owner. |

## Traceability and automation

### Source-to-suite map

| Requirement area | Catalogue prefixes | Primary implementation reference |
|---|---|---|
| Public/private navigation and dashboard | NAV | [Router](../om_sai_ram/lib/core/services/router_service.dart), [features](../om_sai_ram/lib/features/) |
| Identity/session/profile | AUTH, OTP, PROFILE, SEC | [Auth API](../backend/app/routers/auth.py), [auth middleware](../backend/app/middleware/auth.py), [validators](../om_sai_ram/lib/core/utils/validators.dart) |
| Membership and roles | GRP, SEC | [Groups API](../backend/app/routers/groups.py), [group screen](../om_sai_ram/lib/features/groups/presentation/group_detail_screen.dart) |
| Manual/automatic reading assignment | MAN, COM, SCH | [Assignments API](../backend/app/routers/assignments.py), [manual sheet](../om_sai_ram/lib/features/groups/presentation/manual_assignment_sheet.dart), [unit mapping](../backend/app/services/chapter_units.py) |
| Reader/content/languages | READ, COM, LANG | [Content repository](../om_sai_ram/lib/features/reader/data/content_repository.dart), [language state](../om_sai_ram/lib/core/providers/language_provider.dart), [bundled books](../om_sai_ram/assets/content/) |
| Progress and community | PROG, CHAT | [Progress API](../backend/app/routers/progress.py), [chat API](../backend/app/routers/group_chat.py) |
| Reminders | NOTIF | [Local notification service](../om_sai_ram/lib/core/services/notifications_service.dart), [schedule API](../backend/app/routers/notification_schedule.py) |
| Media/live/information | MEDIA, LIVE, INFO | [Audio features](../om_sai_ram/lib/features/audio/), [live API](../backend/app/routers/live_darshan.py), [festival service](../backend/app/services/festival_scraper.py) |
| Nonfunctional/release | A11Y, SEC, RES, OPS | [App](../om_sai_ram/lib/app.dart), [configuration](../backend/app/config.py), [deployment](../backend/docker-compose.yml) |

### Coverage counts

| Family | Cases | Family | Cases |
|---|---:|---|---:|
| Navigation/dashboard | 12 | Email/session/social auth | 22 |
| Phone/OTP | 10 | Profile/account | 10 |
| Groups/membership | 18 | Manual assignments | 18 |
| Combined chapter mapping | 10 | Automatic schedules/suggestions | 20 |
| Reader/content | 14 | Reading progress | 10 |
| Chat/highlights | 12 | Notifications | 14 |
| Audio | 12 | Live Darshan | 6 |
| Events/programme/FAQ | 7 | Languages/content quality | 8 |
| Accessibility/layout | 8 | Security/API contract | 12 |
| Offline/resilience/performance | 10 | Deployment/release | 10 |

Counts describe specification breadth, not automated coverage or pass rates.

### Existing automation baseline

Last verified during implementation of manual assignments: **88 backend tests, 18 Flutter tests passed**. This is a historical snapshot, not a new execution in this documentation task and not a coverage percentage.

| Existing test file | Evidence it provides | What it does not certify |
|---|---|---|
| [Backend auth tests](../backend/tests/test_auth.py) | Selected identity/authentication/validation cases | Provider verification, production SMS, real browser session behavior or exhaustive security |
| [Backend groups/progress tests](../backend/tests/test_groups_and_progress.py) | Selected group, assignment, schedule, progress and error cases on SQLite | PostgreSQL concurrent operations, complete cascade/authorization coverage or client E2E |
| [Backend combined-unit tests](../backend/tests/test_combined_chapters.py) | Canonical unit progression, modes/cycle, manual duplicates, dates and later-week repeat readings | Legacy migration, preview-confirm parity or actual device notifications |
| [Flutter smoke test](../om_sai_ram/test/widget_test.dart) | Basic root rendering | All screens, deep links or full login flow |
| [Flutter combined tests](../om_sai_ram/test/combined_chapters_test.dart) | Range labels, translation deduplication, Marathi group assembly | Linguistic accuracy, reader scroll/navigation or real audio |
| [Flutter manual tests](../om_sai_ram/test/manual_assignment_test.dart) | Server IDs, English fallback, member/week choices, duplicate/partial-failure/retry/keyboard behavior | Real backend connectivity, permission matrix or all responsive platforms |

### Recommended automation order

1. P0 API permission matrix, full auth lifecycle and PostgreSQL transactional/concurrent assignment tests.
2. P0 schedule fixture tests including preview/confirmation equality, combined ranges and all remainder modes.
3. Flutter integration flows for signup/login, manual assignment → reading → completion and logout/account switch.
4. Unit tests for validation/language persistence/content update integrity/notification date computation.
5. Fixture-driven festival/live tests; media/network failure tests; visual/accessibility checks.
6. Real-device notification/audio certification and release-build web/Android smoke suites.

Keep external network out of deterministic unit suites; use explicit integration suites for real hosts. Run SQLite tests for speed **and** PostgreSQL tests for production semantics.

## Execution and defect reporting

### Execution record template

Copy one record per case and parameter/platform combination; store results separately from this specification.

| Field | Value to record |
|---|---|
| Run ID / case ID | e.g. QA-2026-10-13-01 / MAN-04 / Marathi / Android |
| Build and environment | Commit, app/API builds, DB version, device/OS/browser, timezone, locale, network |
| Preconditions and data | Accounts/roles/group/week/chapter/server IDs, stubbed/real external service |
| Exact steps | Include parameter values and any deviation from catalogue |
| Expected result | Assertion from case; approved product decision where risk-based |
| Actual result | Observable UI/API/DB/notification output, not just “works” |
| Status | Not Run / Pass / Fail / Blocked / Not Applicable |
| Evidence | Screenshot/video, redacted HTTP request/response, logs, timestamps, database checks |
| Defect / blocker | Ticket ID, severity, impact, owner, dependency and retest date |
| Tester / execution date | Responsible person and timestamp |

**Blocked** requires a blocker and owner. **Not Applicable** requires a scope reason and approval. Neither counts as Pass. A P0 known defect remains a failure unless the functionality is explicitly removed from release scope and disclosed.

### Defect template

- Title: feature + action + observed failure.
- Environment/build, affected roles/languages/platforms, reproducibility rate.
- Minimal setup and numbered reproduction steps.
- Expected and actual result, redacted evidence, relevant case ID.
- Severity: critical/high/medium/low based on impact; priority assigned separately.
- Data/security impact, workaround, affected release, owner and retest evidence.

### Reporting and maintenance

- Report executed/passed/failed/blocked/not-applicable counts by priority, feature and platform; count parameterized runs consistently.
- Include unresolved defects, integration readiness, content-review approvals and explicit release recommendation.
- Update this catalogue whenever routes, roles, chapter mapping, languages or platform support change.
- For operating instructions see [User guide](USER_GUIDE.md), [project README](../README.md), [Flutter README](../om_sai_ram/README.md), and [backend README](../backend/README.md).