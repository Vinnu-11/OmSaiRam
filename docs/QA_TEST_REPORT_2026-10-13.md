# Om Sai Ram — truthful QA test report, 2026-10-13

**Run:** QA-2026-10-13-01. **Recommendation: RELEASE NOT READY.** P0 findings remain unresolved and certification is incomplete. This is a reconciliation of already-saved execution evidence, not a new test run. No application fixes or expensive test reruns were performed for this report.

Baseline: [243-case catalogue](QA_TEST_CASES.md), [environment record](test-results/QA_RUN_2026-10-13_ENVIRONMENT.json), and [durable compact results](test-results/QA_RUN_2026-10-13_RESULTS.json). Requirements and approvals remain governed by [requirements](REQUIREMENTS.md).

## 1. Status rules and executive result

| Status | Cases | Meaning |
|---|---:|---|
| Pass | 4 | Supplied, explicitly fully scoped evidence: NAV-01 web-only, AUTH-21 web-only, COM-03 structural data, OPS-02 isolated lifespan. Not cross-platform certification. |
| Partial | 114 | **Reporting extension** to the catalogue's status vocabulary: successful executed subset only; **not an exit-criteria Pass**. All successful API-only mappings remain Partial. |
| Fail | 12 | At least one observed failed assertion or quality gate. Fail wins over Partial; provisional oracle caveats are explicitly retained. |
| Blocked | 113 | No execution evidence supporting this case; prerequisites and suggested owner appear below. Not a product-failure verdict. |
| **Accounted** | **243** | Every catalogue ID appears exactly once in the per-case table. **Not all 243 ran or completed.** |

130 catalogue cases have some supporting execution evidence (4 + 114 + 12); only four have the explicitly stated full-scope Pass disposition. There are no inferred Not Applicable exclusions. Successful subchecks must not be substituted for completed catalogue cases.

### Totals by priority

| Priority | Total | Pass | Partial | Fail | Blocked |
|---|---:|---:|---:|---:|---:|
| P0 | 101 | 3 | 71 | 6 | 21 |
| P1 | 139 | 1 | 42 | 6 | 90 |
| P2 | 3 | 0 | 1 | 0 | 2 |
| **Total** | **243** | **4** | **114** | **12** | **113** |

### Totals by family

| Family | Total | Pass | Partial | Fail | Blocked |
|---|---:|---:|---:|---:|---:|
| NAV | 12 | 1 | 3 | 0 | 8 |
| AUTH | 22 | 1 | 14 | 1 | 6 |
| OTP | 10 | 0 | 8 | 0 | 2 |
| PROFILE | 10 | 0 | 8 | 0 | 2 |
| GRP | 18 | 0 | 16 | 0 | 2 |
| MAN | 18 | 0 | 13 | 1 | 4 |
| COM | 10 | 1 | 6 | 0 | 3 |
| SCH | 20 | 0 | 12 | 5 | 3 |
| READ | 14 | 0 | 3 | 0 | 11 |
| PROG | 10 | 0 | 7 | 0 | 3 |
| CHAT | 12 | 0 | 9 | 1 | 2 |
| NOTIF | 14 | 0 | 2 | 0 | 12 |
| MEDIA | 12 | 0 | 0 | 0 | 12 |
| LIVE | 6 | 0 | 1 | 0 | 5 |
| INFO | 7 | 0 | 2 | 0 | 5 |
| LANG | 8 | 0 | 2 | 0 | 6 |
| A11Y | 8 | 0 | 0 | 0 | 8 |
| SEC | 12 | 0 | 5 | 3 | 4 |
| RES | 10 | 0 | 1 | 0 | 9 |
| OPS | 10 | 1 | 2 | 1 | 6 |
| **Total** | **243** | **4** | **114** | **12** | **113** |

## 2. Environment, evidence and retention

- Commit bd24c153e7461f1343f9aec8b1c709b98266a20f, **dirty working tree**, including implementation changes already present. The commit alone is not the tested snapshot; do not assert clean-commit reproducibility.
- Ubuntu 22.04.5 x86_64; Python 3.10.12; Flutter 3.44.4 stable; Dart 3.12.2. Headless Flutter tests and release-web Chromium/Electron browser only; no Android device. Exact app version/build number, browser version, complete locale/timezone/network matrix were not supplied. No iOS/Linux certification.
- New API runner: fresh in-memory SQLite fixtures, foreign keys enabled, chapter IDs 101–153 deliberately different from numbers 1–53; in-process FastAPI TestClient. App lifespan not started in this runner. Synthetic identities, no real SMS/provider/network services. Rate limiter cleared between unrelated scenarios, with expiry tested separately.
- OPS-02 is **separate actual isolated lifespan evidence**: in-memory database and no-op scraper; DEBUG=false/default secret refused startup, configured synthetic secret allowed startup and healthy response. No secret values retained.
- PostgreSQL 16.14 inspected **read-only**: healthy, 53 Marathi rows/53 unique numbers, absent `alembic_version`. This is **not** a migration/restore rehearsal and does **not** prove data loss. No PostgreSQL mutation/concurrency certification.

### Evidence key used in the per-case table

All durable execution summaries and failure reproductions are in [results JSON](test-results/QA_RUN_2026-10-13_RESULTS.json). Exact original temporary paths are recorded under `evidence_retention.transient_originals`; they live under /tmp and may disappear. Original logs were read, not copied or treated as durable attachments.

| Key | Saved execution evidence | Correct interpretation |
|---|---|---|
| A | New [API runner](../backend/qa_catalogue_checks.py); JSON API section: **991 case-tagged subchecks = 971 Pass + 20 Fail**, across **101 IDs**, 90 successful-only and 11 with failures. | Direct API/SQLite subset, never a full catalogue Pass. Checks can be tagged to more than one case. |
| B | Existing backend JUnit XML/log: **88 tests Pass**, zero failure/error/skip; 30.925 s; two Pydantic configuration deprecation warnings. All individual JUnit class/name results persisted in JSON. | Real saved suite results, not 88 additional completed catalogue rows. SQLite fixtures are not production PostgreSQL evidence. |
| F | Existing Flutter log: **18 tests Pass**, zero Fail; final +18 All tests passed. Source-inspected composition: one smoke, ten combined-unit, two manual repository, five manual widget tests. | Interleaved log repeats smoke labels; not 13 distinct smoke tests. Headless/mocked repository tests, not full devices/E2E. |
| D | **145 structural checks Pass**, zero Fail: COM-03 108, READ-01 18, LANG-06 18, LANG-01 1; 18 languages/852 chapter entries. | All per-check statuses and expected/actual values preserved in compact language matrix. No linguistic/source/OCR/font approval. |
| E | [Environment browser/additional-case evidence](test-results/QA_RUN_2026-10-13_ENVIRONMENT.json). | Scope-limited observed web, data, health and lifespan evidence. Browser timeouts are inconclusive. |
| Q | Saved analyzer and web build logs, summarized in JSON/environment. | Analyzer exit 1: **378 info, 0 warning, 0 error**, untriaged. JavaScript web release build succeeds (66.5 s); Wasm dry-run/font warnings are not a failed JS compilation. |
| — | No supporting execution for this case. | Explicit Blocked; action/reviewer/configuration prerequisites and owner below. |

Durable API retention is intentionally compact: all 101 case-level Pass/Fail counts and representative named checks with expected/actual, plus all 20 failed tags as 16 distinct assertion records, exact relevant inputs, expected/actual grids and caveats. The 971 individual successful check names/values and repeated raw request prefixes are **not all copied**; full traces remain transient. Representatives are samples, not an assertion that every passing check had that name or value. Data matrix is lossless for the 145 structural results. No credentials, JWT values or production personal data are included.

### Mapping discipline

[Backend combined tests](../backend/tests/test_combined_chapters.py) assert unit progression, starts inside ranges and retained chapter 50 in truncation. [Flutter combined tests](../om_sai_ram/test/combined_chapters_test.dart) assert English fixture deduplication, Marathi fixture assembly/separate standalone lookup, and assignment/preview labels. Therefore COM-01/02/04/05/08/09 are **Partial**, with explicit missing scope. COM-08 is **only scheduling retains 50**, not a proven reader fallback. COM-06 stays **Blocked**: [existing progress tests](../backend/tests/test_groups_and_progress.py) use chapter 3, not combined local-range completion; no local-history assertion supports that row. COM-07 reader traversal and COM-10 legacy history are not certified by unit helpers.

[Manual tests](../om_sai_ram/test/manual_assignment_test.dart) support MAN-07 English-index fallback/load retry, MAN-15 partial-save/retry, MAN-16 retry-loading only, MAN-17 keyboard inset/no exception only. MAN-10 selection-clearing and MAN-12 search remain **Blocked**: their required assertions are absent. No speculative mapping is made from test names alone.

## 3. Detailed failures and exact reproduction inputs

**20 tagged failed API subchecks represent 16 distinct assertions**, across 11 case IDs. F01–F03 each carry two tags; F10 carries two tags; all others one: 6 + 2 + 12 = 20. OPS-08 is a separate quality-gate failure, making **12 failed catalogue IDs**, not 21 failed API checks. F labels are local report references, not filed issue tickets. Priorities are catalogue priorities, not automatic defect severity; suggested owners must triage impact and sign off.

Reproduce only in authorized isolated fixtures. API prefix is /api/v1. A is G1 admin; M1 its member; X is G2 outsider. Chapter 102 means original 2. Scheduling fixtures use ordered members and current week 1, with W as readings/member/week. See [runner fixture setup](../backend/qa_catalogue_checks.py) for seeded synthetic roles. Credentials are deliberately redacted; generate fresh test values locally rather than copying secrets.

| Finding | Catalogue tags / failed tags | Exact input / setup | Expected → observed | Caveat / suggested owner |
|---|---|---|---|---|
| F01 | AUTH-17, SEC-05 / 2 | Exchange A's original refresh once; POST /api/v1/auth/refresh with refresh_token = retained original (redacted). | Safety oracle 401 → 200 on replay. | Known stateless-token finding; security signoff/revocation policy required. Logout replay not separately executed. Security + API owner. |
| F02 | AUTH-17, SEC-05 / 2 | Successful POST /api/v1/auth/change-password using redacted current_password/new_password; GET /api/v1/auth/me with pre-change access JWT. | Safety oracle 401 → 200. | Retained access validity after password change, not token-tampering bypass. Security + API owner. |
| F03 | AUTH-17, SEC-05 / 2 | After same password change, POST /api/v1/auth/refresh with pre-change refresh_token (redacted). | Safety oracle 401 → 200. | Retained refresh validity; requires explicit security disposition. Security + API owner. |
| F04 | MAN-11 / 1 | A POST /api/v1/assignments: group_id=G1,user_id=M1,chapter_id=102,week_number=1000000000. | Runner 400 → 500. **Any controlled 4xx is acceptable**, not only 400. | Uncontrolled large-week/date overflow; UI validation scope incomplete. API owner. |
| F05 | SCH-12 / 1 | N=1,W=53; A POST /api/v1/assignments/auto-schedule: group_id=G1,weeks_ahead=1,remainder_mode=cycle. | requested=53,created=48,reported_unfilled=5 → 53,48,0. | 48 unique units correctly avoid duplicates; five skipped slots lack accounting. Not 48 missing readings. API + product owner. |
| F06 | SCH-16 / 1 | A POST /api/v1/assignments/suggest: group_id=G1,hints=[{position:0,chapter_start:1},{position:99,chapter_start:3}],weeks_ahead=1. | Runner validation oracle 400 → 200. | Nonexistent position accepted; ambiguous-input finding pending intended contract. Product + API owner. |
| F07 | SCH-16 / 1 | Same route: group_id=G1,hints=[{position:0,chapter_start:1},{position:0,chapter_start:3}],weeks_ahead=1. | Runner validation oracle 400 → 200. | Duplicate-position acceptance, not proof of stored corruption. Product + API owner. |
| F08 | SCH-15 / 1 | Same route: group_id=G1,hints=[{position:0,chapter_start:3},{position:1,chapter_start:1}],weeks_ahead=1. | Runner validation oracle 400 → 200. | Reversed/negative-step acceptance; approve validation semantics. Product + API owner. |
| F09 | CHAT-05 / 1 | Seed same0/same1/same2 in G1 for M1 at 2026-01-01T00:00:00. M1 GET /api/v1/groups/G1/messages?limit=1 then ?limit=100&before_id=same0. | Traverse all 3 → only 1; two tied-time messages missed. | **Unambiguous pagination loss**, not physical DB deletion. API owner. |
| F10 | CHAT-05, SEC-02 / 2 | Seed foreign in G2/X at 2026-01-02T00:00:00; M1 GET /api/v1/groups/G1/messages?before_id=foreign. | Assumed rejection oracle 404 → 200. | Foreign timestamp influences cursor; **does not prove G2 message-body disclosure**. Confirm cursor contract. Security + API owner. |
| F11 | CHAT-05 / 1 | M1 GET /api/v1/groups/G1/messages?before_id=missing. | Assumed unknown-cursor oracle 404 → 200. | Confirm intended behavior; F09 remains unambiguous independently. Product + API owner. |
| F12 | SEC-08 / 1 | Loaded CORS origins=[*]. OPTIONS /api/v1/groups with Origin=https://untrusted.invalid, Access-Control-Request-Method=GET, Access-Control-Request-Headers=authorization. | [400,no allow-origin] → [200,*]. | Isolated loaded-default **CONFIGURATION safety failure**, not a production assertion. OPTIONS reconstructed from inspected runner; raw trace's last PATCH is unrelated. DevOps + security owner. |
| F13 | SCH-10 / 1 | N=1,W=2; A POST /api/v1/assignments/auto-schedule: group_id=G1,start_chapter=49,weeks_ahead=2,remainder_mode=extend_last. | Runner unfilled-count oracle 1 → 0; allocations 49,50,51. | Desired approved allocation absent; **provisional oracle**, observed missing accounting stated separately. Product/reading lead + API owner. |
| F14 | SCH-10 / 1 | Same fixture/input, remainder_mode=round_robin. | Runner wrap oracle [49,50,51,1] → [49,50,51]. | Observed truncation. Wrapping is not an approved business rule; expectation approval required. Product/reading lead + API owner. |
| F15 | SCH-17 / 1 | N=3 ordered A,M1,M2,W=2. POST /api/v1/assignments/suggest: group_id=G1,week_number=1,weeks_ahead=1,hints=[{position:0,chapter_start:1},{position:1,chapter_start:3}]; confirm POST /api/v1/assignments/auto-schedule: group_id=G1,start_chapter=1,weeks_ahead=2,schedule_mode=independent. | Preview week2 A=3/4,M1=5/6,M2=7/8 → saved A=7/8,M1=9/10,M2=11/12. | **Unambiguous preview-confirm grid mismatch**; full 12-cell grids in JSON. API + client owner. |
| F16 | SCH-17 / 1 | Same as F15, second hint chapter_start=4 (custom step3); confirm same independent request. | Preview week1 M1=4/5,M2=7/8 → saved M1=3/4,M2=5/6; week2 also differs. | Custom mapping falls back to independent. Full grids preserved; dense-window parity passes. API + client owner. |
| Q01 | OPS-08 / not API | Saved backend/Flutter suites and analyzer evidence; no rerun. | 88/18 suite tests Pass; analyzer exits1 with 378 info,0 warning,0 error; no lint triage/security scan. | **Quality-gate/triage failure, not compiler errors or proven vulnerabilities.** Engineering lead + security owner. |

AUTH-17/SEC-05 require explicit security approval of retained-JWT lifetime or implemented revocation, rather than a fake Pass. SCH-10 requires lead-approved remainder allocations before definitive business-rule retest. SCH-15/16 are ambiguous acceptance findings. Release is still not ready even if these policy oracles change, because preview-confirm parity and tied-time pagination loss are unequivocal and many critical cases remain uncertified.

## 4. Per-case results — all 243 identifiers, exactly once

The expected/observed column describes only a concise assertion subset, not replacement of the complete catalogue. **A p/f** means saved API passing/failed subcheck counts; it does not mean the whole case ran. Owners are suggested accountable roles, not evidence of assigned tickets. A dash means no observed result. Blockers on Partial rows describe missing scope; Blocked rows name the unexecuted prerequisite. Pass rows retain their explicit scope.

### NAV — launch/navigation

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| NAV-01 | P0 | Pass | Guest home/public reader reachable → fresh release-web origin loaded. | E | None within web-only scope; Android launch still uncertified. |
| NAV-02 | P1 | Blocked | Saved-session cold/warm restoration → not observed. | — | Seeded browser/device session and restart sequence; Client QA. |
| NAV-03 | P0 | Partial | Guest private routes denied → groups/profile redirected to login; private API sample denied. | E,A | Deep-link/platform matrix and all private controls; Client QA. |
| NAV-04 | P1 | Partial | Public routes without login → reader/events/programme/FAQ/live accessible. | E | Audio browser timeout inconclusive; audio/device/public-route matrix; Media + Client QA. |
| NAV-05 | P1 | Blocked | Authenticated auth-route redirect → not observed. | — | Logged-in browser/device navigation fixture; Client QA. |
| NAV-06 | P1 | Blocked | Tabs/back consistent → not observed. | — | Android back and browser-history repeated-navigation run; Client QA. |
| NAV-07 | P1 | Blocked | Hosted deep-link refresh works → not observed. | — | HTTPS SPA hosting and seeded group/new-tab session; DevOps + Client QA. |
| NAV-08 | P1 | Partial | Controlled not-found → reader/999 and unknown route show not-found. | E | Nonnumeric check timed out, no defect verdict; group/platform matrix; Client QA. |
| NAV-09 | P1 | Blocked | Nested failing request keeps route → not observed. | — | Controlled request failure/auth transition fixture; Client QA. |
| NAV-10 | P1 | Blocked | Dashboard counts track mutations → not observed. | — | Two-user E2E join/assign/complete/remove fixture; Client QA. |
| NAV-11 | P2 | Blocked | Empty/long-name dashboard usable → not observed. | — | Empty/long-name responsive visual fixture; Client QA. |
| NAV-12 | P1 | Blocked | Modal cancellation causes no write → not observed. | — | Modal/focus/back/scrim device matrix; Client QA. |

### AUTH — email/session/social

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| AUTH-01 | P0 | Partial | Unique signup → API account/tokens created, Unicode name trimmed. | A 2/0,B | Real client confirmation/authenticated flow; Client QA. |
| AUTH-02 | P1 | Partial | Name validation/Unicode → API boundary subset accepted/rejected. | A 7/0 | UI limits and full name matrix; Client QA. |
| AUTH-03 | P1 | Partial | Email validation/normalization → duplicate mixed-case and malformed subset checked. | A 5/0,B | All UI/overlong boundaries; Client QA. |
| AUTH-04 | P0 | Partial | Duplicate identifiers controlled → API conflicts rejected. | A 2/0,B | Client conflict presentation/PostgreSQL unique semantics; API + Client QA. |
| AUTH-05 | P1 | Partial | Password length bounds → API 0/7/8/128/129 plus spaces/Unicode subset checked. | A 7/0 | UI boundary/visibility/entry behavior; Client QA. |
| AUTH-06 | P1 | Blocked | Confirmation/visibility/paste safe → not observed. | — | Real auth-form widget/browser interactions; Client QA. |
| AUTH-07 | P0 | Partial | Correct mixed-case login → API 200. | A 1/0,B | Client restore and client logging inspection; Client QA + security. |
| AUTH-08 | P0 | Partial | Generic failures → wrong/unknown account same credential detail. | A 1/0,B | Client session/form behavior; Client QA. |
| AUTH-09 | P1 | Blocked | Double-submit/disposal safe → not observed. | — | Delayed auth response/double-tap/navigation harness; Client QA. |
| AUTH-10 | P0 | Partial | Failed-login threshold/expiry → API attempt and monotonic expiry checks pass. | A 13/0 | Multi-worker/restart abuse behavior; API + DevOps. |
| AUTH-11 | P1 | Blocked | Offline/timeout/500 login recoverable → not observed. | — | Network fault fixture and real forms; Client QA. |
| AUTH-12 | P0 | Partial | Invalid access JWT denied → malformed/expired/tampered/type subset rejected. | A 6/0,B | Exhaustive endpoint/token matrix and production security review; Security QA. |
| AUTH-13 | P0 | Partial | Valid refresh works → new access and profile API work. | A 2/0,B | Client refresh/interceptor retries, including me; Client QA. |
| AUTH-14 | P0 | Partial | Deleted-user tokens denied → retained access/refresh rejected. | A 2/0 | UI expiry/refresh401/no-loop recovery; Client QA. |
| AUTH-15 | P0 | Blocked | Cancel/confirm logout clears storage/reminders → not observed. | — | Device/browser persistence and queued-reminder fixture; Client QA. |
| AUTH-16 | P1 | Partial | Invalid refresh claims denied → API six rejection checks. | A 6/0,B | Remaining token-contract/security review; Security QA. |
| AUTH-17 | P0 | Fail | Replay/password-change safety oracle → retained JWT requests 200. | A 0/3,F01–03 | Known stateless security finding needs signoff/revocation; logout portion untested. Security + API. |
| AUTH-18 | P1 | Blocked | Concurrent401/failing refresh no recursion → not observed. | — | Parallel client HTTP401 harness and independent sessions; Client QA. |
| AUTH-19 | P1 | Partial | Unsupported Google/invalid provider controlled → 501/no-session subset. | A 3/0 | Provider cancellation UI; successful social path absent/config approval; Identity + Client QA. |
| AUTH-20 | P1 | Partial | Unsupported Apple controlled → 400/no-session subset. | A 2/0 | Provider cancellation/platform setup; successful integration absent; Identity + Client QA. |
| AUTH-21 | P1 | Pass | Honest recovery affordance → release-web Password reset coming soon. | E | None within supplied web-login scope; no working reset claimed. |
| AUTH-22 | P0 | Blocked | No cross-account private state → not observed. | — | A→M1 same-device/separate-tab cache/token/reminder audit; Security + Client QA. |

### OTP — phone authentication

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| OTP-01 | P1 | Partial | Formatted phone/OTP fixture → API normalization/expiry subset passes. | A 2/0 | Phone UI and real sender not exercised; Identity + Client QA. |
| OTP-02 | P1 | Partial | Invalid phone rejected → six API checks pass. | A 6/0 | UI full formatting matrix; Client QA. |
| OTP-03 | P0 | Partial | Existing phone logs into same account → API200/used-record subset. | A 2/0 | Real delivery/client session; Identity + Client QA. |
| OTP-04 | P0 | Partial | Name retry retains OTP → initial404 then creates one phone account. | A 3/0,B | Client multi-step/new-account E2E; Client QA. |
| OTP-05 | P0 | Partial | Wrong/expired/used credentials denied → API rejection subset. | A 3/0 | Complete device/phone/session matrix; Identity QA. |
| OTP-06 | P1 | Partial | Length/verification validation → six API checks; digit-only UI not certified. | A 6/0 | Alphabetic/whitespace UI versus schema matrix; Client QA. |
| OTP-07 | P0 | Partial | Verification throttle/expiry → API threshold/monotonic expiry pass. | A 7/0 | Alternate-format/multi-worker production abuse policy; API + security. |
| OTP-08 | P1 | Partial | Resend invalidates old/throttles → API newest-record/rate subset passes. | A 8/0 | UI resend state and SMS delivery; Identity + Client QA. |
| OTP-09 | P1 | Blocked | Back/cancel/network recovery safe → not observed. | — | Phone/OTP/name step browser/device fault fixture; Client QA. |
| OTP-10 | P0 | Blocked | Real SMS and safe production logging → not observed. | — | Production sender absent; authorized delivery/log-redaction environment; Identity + DevOps/security. |

### PROFILE — preferences/account

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| PROFILE-01 | P1 | Partial | Own updates persist → API Unicode/profile changes checked. | A 7/0 | Client restart and chat-name refresh; Client QA. |
| PROFILE-02 | P1 | Partial | Invalid PATCH leaves profile safe → API400/422 subset. | A 8/0 | UI/avatar/full-boundary presentation; Client QA. |
| PROFILE-03 | P0 | Partial | Primary identifier cannot be cleared → API400. | A 2/0,B | Full account-provider/PostgreSQL contract; API QA. |
| PROFILE-04 | P0 | Partial | Password change/new login → API successful; old credentials tested separately from JWT validity. | A 8/0 | Client handling/restart; F02–03 safety finding separate; Client QA + security. |
| PROFILE-05 | P1 | Partial | Invalid current/provider/password rejected → API subset. | A 4/0 | UI confirmation and full boundary matrix; Client QA. |
| PROFILE-06 | P1 | Blocked | Dark preference/readability persists → not observed. | — | Theme/restart/all-screen contrast device run; Client QA. |
| PROFILE-07 | P1 | Blocked | Version/help links accurate → not observed. | — | Release metadata and external-link audit; Release + Client QA. |
| PROFILE-08 | P0 | Partial | Admin deletion blocked/eligible deletion succeeds → API subset. | A 7/0 | Cancellation/role-resolution real client flow; Client QA. |
| PROFILE-09 | P0 | Partial | Deleted data scrubbed/tokens denied → isolated API anonymization checks. | A 5/0 | PostgreSQL retained-reference/PII audit; Security + DB QA. |
| PROFILE-10 | P0 | Partial | Eligible account API delete → 204/anonymization subset. | A 2/0 | Active media/reminders/reopen/cache cleanup on device; Client + security QA. |

### GRP — groups/membership

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| GRP-01 | P0 | Partial | Group defaults/admin/invite → API creation assertions pass. | A 3/0,B | Client create/reload flow; Client QA. |
| GRP-02 | P1 | Partial | Name/description bounds → API subset checked. | A 6/0 | UI1/2/80/81 and Unicode matrix; Client QA. |
| GRP-03 | P1 | Partial | Modes/settings validation → API ten checks. | A 10/0,B | UI configuration; no seven-day algorithm inferred; Client QA. |
| GRP-04 | P1 | Partial | Only own memberships → API list subset checked. | A 2/0,B | Many-group cards/pull-refresh/empty UI; Client QA. |
| GRP-05 | P0 | Partial | Trim/lowercase invite → normalized API join200. | A 1/0,B | UI count/role refresh across devices; Client QA. |
| GRP-06 | P1 | Partial | Invalid/duplicate invite controlled → API subset checked. | A 7/0,B | UI4–20 versus API4–8 discrepancy; Client QA. |
| GRP-07 | P0 | Partial | Guest/outsider group denied → permission subset passes. | A 10/0,B | Full known-UUID private response matrix/PostgreSQL; Security QA. |
| GRP-08 | P1 | Blocked | Safe clipboard/share/fallback → not observed. | — | Native/browser share APIs and cancel/unsupported fixture; Client QA. |
| GRP-09 | P1 | Partial | Admin settings persist → API200/state subset. | A 2/0 | Second-device reload/existing assignment history; Client QA. |
| GRP-10 | P0 | Partial | Admin-only write denied to others → API checks/fingerprints pass. | A 15/0 | UI lead controls/permissions refresh; Client QA. |
| GRP-11 | P1 | Partial | Admin promotion/invalid role controlled → API subset. | A 4/0 | Demotion/self/nonmember UI and active client refresh; Client QA. |
| GRP-12 | P1 | Partial | Authorized search/cap/masking → API subset passes. | A 5/0 | Client name/email/phone/many-results presentation; Client QA. |
| GRP-13 | P0 | Partial | Unauthorized/unknown/add denied → API permission checks. | A 12/0 | Exhaustive PII/PostgreSQL contract; Security + DB QA. |
| GRP-14 | P0 | Partial | Member removed/assignments cleaned → isolated API state checked. | A 11/0 | Other-device UI/reminders/PostgreSQL cleanup; Client + DB QA. |
| GRP-15 | P0 | Partial | Self/admin/lead restrictions → API subset. | A 4/0 | Remaining role/target/platform matrix; Security QA. |
| GRP-16 | P0 | Partial | Leave/admin block/cleanup → API assignment/progress cleanup passes. | A 17/0,B | Cancel UI/reminder cleanup/PostgreSQL; Client + DB QA. |
| GRP-17 | P0 | Partial | Populated group delete → FK-enabled SQLite deletes dependencies without500. | A 11/0 | PostgreSQL cascades and client former-member recovery; DB + Client QA. |
| GRP-18 | P1 | Blocked | Concurrent membership/delete consistent → not observed. | — | Two-device PostgreSQL concurrency fixture; DB + Client QA. |

### MAN — manual assignments

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| MAN-01 | P0 | Partial | Selected member/week/not-started → API writes; mocked widget selected week/count. | A 7/0,B,F | Real client/API parent refresh and role matrix; Client QA. |
| MAN-02 | P1 | Blocked | Empty/populated entry/permissions UI → not observed. | — | Role-based group-page entry fixtures; Client QA. |
| MAN-03 | P0 | Partial | Nonconsecutive1/8/20 → API selected-record subset checked. | A 4/0 | Real chooser/E2E no intervening units; Client QA. |
| MAN-04 | P0 | Partial | Ranges canonical/atomic → API interiors and widget16–17/18–19 labels. | A 8/0,F | All four ranges real chooser/progress E2E; Client QA. |
| MAN-05 | P0 | Partial | Interior IDs normalize → API canonicalization subset. | A 8/0,B | Full persisted/server range contract; API QA. |
| MAN-06 | P0 | Partial | IDs differ from numbers → API101+ fixtures and widget216/218 retained. | A 2/0,F | Real client/server integrated request capture; Client QA. |
| MAN-07 | P1 | Partial | Marathi preferred/English fallback/retry → repository empty-mr fallback; load-failure Retry widget. | F | Truly absent both indexes and real network/device matrix; Client QA. |
| MAN-08 | P0 | Partial | Same-week range duplicates denied → API400 and disabled widget unit. | A 2/0,B,F | Legacy split records/real chooser/PostgreSQL; API + Client QA. |
| MAN-09 | P0 | Partial | Legitimate member/week/group repeats → API subset and later-week tests. | A 3/0,B,F | Full cross-group/client E2E matrix; Client QA. |
| MAN-10 | P1 | Blocked | Context change clears selection → **no assertion proves clearing**. | — | Select then change member/week and assert selection/indicators; Client QA. |
| MAN-11 | P1 | Fail | Controlled week boundaries → 1e9 returns500; lower bounds/widget0 checked. | A 3/1,F,F04 | Overflow needs controlled4xx; all blank/text/large UI checks incomplete; API + Client QA. |
| MAN-12 | P1 | Blocked | Search/filter selection persists → **no search assertion present**. | — | Number/range/title/no-match/clear widget fixtures; Client QA. |
| MAN-13 | P0 | Partial | Unknown chapter/nonmember/group denied → API rejection subset. | A 3/0,B | Removed/deleted/PostgreSQL orphan matrix; API + DB QA. |
| MAN-14 | P1 | Partial | Default relative Monday/explicit date retained → API/date assertions pass. | A 4/0,B | Other clock/timezone/calendar boundaries; API QA. |
| MAN-15 | P0 | Partial | Second save fails, retry only unsaved → calls216,218,218; first unchecked/second selected. | F | Real HTTP partial failure/parent refresh E2E; Client QA. |
| MAN-16 | P1 | Partial | Loading retry usable → load error/Retry reopens choices. | F | **No slow-save/double-tap/disposal assertion**; delayed device/widget fixture; Client QA. |
| MAN-17 | P1 | Partial | Keyboard inset safe → inset240, no exception, week/Save found. | F | Landscape/small/tablet/large text/reachability matrix; Client QA. |
| MAN-18 | P0 | Blocked | Concurrent unit posts produce at most one pair → not observed. | — | PostgreSQL simultaneous-write/uniqueness fixture; DB + API QA. |

### COM — combined chapters

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| COM-01 | P0 | Partial | 15→16–17→18–19→20 → exact server unit sequence asserted. | B | Real group/member reader/completion E2E; Client QA. |
| COM-02 | P0 | Partial | Starts17/19/44/52/53 normalize → parameterized server sequences pass. | B | Real client labels/progression/cycle E2E; Client QA. |
| COM-03 | P0 | Pass | All book mappings/ranges → 18 assets, 108 checks, separate mr1–53; translation47. | D,E | None within structural DATA scope; hyphen/en-dash equivalent. Not linguistic approval. |
| COM-04 | P0 | Partial | Translation unit read once → four English mock-repository ranges return same chapter. | F | Every selectable language/real bodies and labels in client; Content + Client QA. |
| COM-05 | P0 | Partial | Marathi group assembly/separate standalone → fixture originals contained; standalone lookup same original. | F | Full real bodies/exact-once linguistic/UI review; Marathi reviewer + Client QA. |
| COM-06 | P0 | Blocked | Combined completion/server+local originals → not asserted; generic chapter3 progress insufficient. | — | Combined assignment/device local-history/server-record fixture; Client QA. |
| COM-07 | P1 | Blocked | Reader prev/next range navigation → not executed in reader. | — | Full translated/mr reader traversal; helpers alone insufficient; Client QA. |
| COM-08 | P0 | Partial | Chapter50 not dropped in scheduling → server truncation asserts49,50,51. | B | **Reader Marathi fallback not tested**; missing-translation fixture; Content + Client QA. |
| COM-09 | P1 | Partial | Full range labels → assignment/preview model labels asserted. | F | Cards/reminders/completion/next-start controls; Client QA. |
| COM-10 | P0 | Blocked | Legacy split history preserved → not observed. | — | Seed16/week1+17/week2 with completed history and approved regeneration policy; API + product QA. |

### SCH — automatic schedules/suggestions

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| SCH-01 | P0 | Partial | Independent N3W2 allocation → API201/grid assertions. | A 2/0,B | Real client/PostgreSQL multi-member E2E; API + Client QA. |
| SCH-02 | P0 | Partial | Rotating-window grid → API expected units checked. | A 2/0,B | UI/PostgreSQL/history matrix; API + Client QA. |
| SCH-03 | P0 | Partial | Dense-window grid → API expected units checked. | A 2/0,B | UI/PostgreSQL/history matrix; API + Client QA. |
| SCH-04 | P0 | Partial | Synchronized grid → API unit identities checked. | A 2/0,B | Real client/global-dedup regression E2E; Client QA. |
| SCH-05 | P0 | Partial | Four modes/unit positions → 72 API checks across N/W/start fixtures. | A 72/0,B | Release UI/PostgreSQL full matrix; API + Client QA. |
| SCH-06 | P1 | Partial | Schema bounds controlled → API weeks/mode/start subset passes. | A 8/0 | UI boundaries/book-end explanations; Client QA. |
| SCH-07 | P1 | Blocked | Stable join ordering/history → not observed for tied joins/new member. | — | Identical join-time/add-member PostgreSQL fixture and documented order; API + product QA. |
| SCH-08 | P0 | Partial | Final-unit cycle → [51,1] asserted. | A 2/0,B | Full API persistence/production DB retest; API QA. |
| SCH-09 | P0 | Partial | Book-end manual/truncate →49,50,51 and remainder subset. | A 10/0,B | Full approved remainder/client descriptions; Product + Client QA. |
| SCH-10 | P1 | Fail | Remainder behavior → extend_last unfilled0; round_robin truncates49,50,51. | A 10/2,F13–14 | **Approved desired allocation absent; provisional oracles**; reading lead/product + API. |
| SCH-11 | P0 | Partial | Rerun skips same user/week units →80 API checks incl fixture reruns. | A 80/0,B | Full manual/legacy/PostgreSQL concurrent matrix; API + DB QA. |
| SCH-12 | P0 | Fail | W53 cycle unique48 but accounting → unfilled0 instead of5. | A 2/1,F05 | Explain reduced slot count; API + product owner. |
| SCH-13 | P1 | Blocked | Next-unscheduled control after range/end → not observed. | — | Real group controls/book-complete state fixture; Client QA. |
| SCH-14 | P0 | Partial | Hint modes/steps → non-overlap/dense/custom detection API checks. | A 6/0,B | UI slot labels/manual/computed display; Client QA. |
| SCH-15 | P0 | Fail | Combined step checks pass; reversed hints accepted200. | A 2/1,F08 | Ambiguous/negative-step contract approval and validation; Product + API. |
| SCH-16 | P1 | Fail | Too-few rejected; position99/duplicate position accepted200. | A 1/2,F06–07 | Ambiguous-input requirement approval; UI help/one-member matrix; Product + API. |
| SCH-17 | P0 | Fail | Preview equals saved → independent/custom grids differ; dense parity passes. | A 4/2,F15–16 | Unambiguous mismatch needs API/client mapping fix and full E2E retest; API + client owner. |
| SCH-18 | P1 | Partial | Preview writes nothing → API metadata/zero-row subset passes. | A 6/0 | Complete label/response/UI contract; API + Client QA. |
| SCH-19 | P0 | Partial | Authorized advance/denial → API increment/permission subset. | A 5/0,B | Client previous/future navigation and stale-history E2E; Client QA. |
| SCH-20 | P0 | Blocked | Concurrent/bounded large scheduling → not observed. | — | PostgreSQL parallel schedule/advance fixture and approved N×W×weeks budget; DB/performance QA. |

### READ — reader/history/content

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| READ-01 | P0 | Partial | Bodies load → English1 web rendered; all18 asset bodies/titles nonempty. | E,D,B | First/middle/final real rendering in all17 selectable languages; Content + Client QA. |
| READ-02 | P1 | Blocked | Supported chapter search correct → not observed. | — | Reader query/clear/no-match fixtures; Client QA. |
| READ-03 | P1 | Blocked | Font bounds/persistence readable → not observed. | — | Device font-limit/restart/verse/long-paragraph matrix; Client QA. |
| READ-04 | P1 | Blocked | Correct bookmark identity persists → not observed. | — | Singleton/combined/language restart fixtures; Client QA. |
| READ-05 | P1 | Blocked | Scroll resume bounded/no false completion → not observed. | — | Short/long chapter layout and cold-restart device fixture; Client QA. |
| READ-06 | P0 | Partial | API unavailable bundled reading → English1 rendered6710 semantics chars with API aborted. | E | Asset server remained reachable; full installed airplane-mode/all-language test needed; Client QA. |
| READ-07 | P1 | Partial | Invalid chapter controlled → API99 returns404; web999 not-found. | B,E | Missing translation/Marathi fallback and absent fallback matrix; Content + Client QA. |
| READ-08 | P0 | Blocked | Safe version/cache update → no older/equal/newer/malformed replacement execution. | — | Versioned full/partial/malformed server fixtures and cache inspection; Content + Client QA. |
| READ-09 | P1 | Blocked | Language-fetch race scoped → not observed. | — | Delayed per-language responses/rapid switching fixture; Client QA. |
| READ-10 | P1 | Blocked | Local streak/history not inflated → not observed. | — | Controlled clock/midnight/reinstall persistence fixture; Client QA. |
| READ-11 | P0 | Blocked | No prior-account reading state exposure → not observed. | — | Same-device A→M1 bookmark/history policy and privacy audit; Security + product QA. |
| READ-12 | P1 | Blocked | Full-book navigation bounds → not executed in reader. | — | Every-entry real-reader traversal/platform matrix; Client QA. |
| READ-13 | P1 | Blocked | Public/group/deep-link context correct → not observed. | — | Seeded assignment/public links and refresh with state inspection; Client QA. |
| READ-14 | P0 | Blocked | No missing/duplicated passages → not source-reviewed. | — | Permitted originals and competent reviewers per language/chapter; Content lead. |

### PROG — progress/completion

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| PROG-01 | P0 | Partial | Own three-status update → API timestamps/record subset passes. | A 6/0,B | M2 real-client refresh/display; Client QA. |
| PROG-02 | P0 | Partial | Nonassignee incl admin/lead denied →API403 subset. | A 9/0,B | Full ownership/group/DB matrix; Security + API QA. |
| PROG-03 | P1 | Partial | Invalid/missing progress controlled → API422/404/creation subset. | A 10/0,B | Full response/PostgreSQL uniqueness matrix; API QA. |
| PROG-04 | P1 | Blocked | Threshold prompt appears once → not observed. | — | Reader scroll95% threshold/widget/device fixture; Client QA. |
| PROG-05 | P0 | Partial | Server complete → API own-completed200 only. | A 1/0,B | Local range history/chat/reminder cancel/prompt E2E; Client QA. |
| PROG-06 | P1 | Blocked | Later/dismiss/public reader no false write → not observed. | — | Prompt cancellation/public reader server-write capture; Client QA. |
| PROG-07 | P0 | Blocked | Partial completion failure recoverable → not observed. | — | Local persistence/chat faults after server commit; Client QA. |
| PROG-08 | P0 | Partial | Assignment/progress delete permitted/denied → API state subset. | A 8/0 | Queued device reminder cancellation/other-device stale reader; Client QA. |
| PROG-09 | P1 | Partial | Revert permitted → API status transitions checked. | A 6/0 | Reminder reschedule/labels after revert; Client QA. |
| PROG-10 | P0 | Partial | Leave/removal revokes activity → API cleanup/access checks pass. | A 18/0 | Actual open reader/chat stale-write UI recovery; Client QA. |

### CHAT — messages/highlights

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| CHAT-01 | P0 | Partial | Unicode multiline send → API201/body/author subset. | A 7/0 | M2 client refresh/render/time presentation; Client QA. |
| CHAT-02 | P1 | Partial | Blank/length validation → API five checks. | A 5/0 | Loading/double-send UI interaction; Client QA. |
| CHAT-03 | P0 | Partial | Outsider/nonowner denied → API permission subset. | A 12/0 | Full browser/device authorization presentation; Security QA. |
| CHAT-04 | P1 | Partial | Authorized moderation/wrong-group safe → API subset. | A 8/0 | Client removal/display and DB retest; Client QA. |
| CHAT-05 | P1 | Fail | Bounds pass; tied-time cursor loses2/3, foreign/unknown accepted200. | A 4/3,F09–11 | Stable tie-break pagination; rejection semantics approval; API + product. |
| CHAT-06 | P1 | Blocked | Large/offline history/reconnect usable → not observed. | — | Large-history network-fault/two-client fixture; Client QA. |
| CHAT-07 | P0 | Partial | Real chapter-ID highlight stored → API201/subset. | A 7/0 | Real rendered anchor/comment/author E2E; Client QA. |
| CHAT-08 | P1 | Partial | Highlight bounds/no orphan → API11 checks. | A 11/0 | Full whitespace/DB boundary contract; API QA. |
| CHAT-09 | P0 | Partial | Filter/owner/moderator/isolation → API19 checks. | A 19/0 | Client filtered rendering and controls; Client QA. |
| CHAT-10 | P1 | Blocked | Highlight navigation meaningful → not observed. | — | Supported UI anchor/language/range fixtures and product scope; Client QA. |
| CHAT-11 | P0 | Partial | Deleted sender anonymized → API preserved-reference subset. | A 4/0 | Real retained-message/highlight UI crash/PII inspection; Security + Client QA. |
| CHAT-12 | P0 | Partial | Script/SQL-like input inert → API literal stored/user count unchanged. | A 2/0 | **Rendering/XSS/URL execution not tested**; browser security QA. |

### NOTIF — native reminders

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| NOTIF-01 | P1 | Blocked | Daily delivery/persistence → not observed. | — | Real Android device, granted permission, pending/delivered inspection; Native QA. |
| NOTIF-02 | P1 | Blocked | Denial/revoke/repermission handled → not observed. | — | Android OS permission/time-change fixture; Native QA. |
| NOTIF-03 | P1 | Blocked | Disable cancels/daily verse rotates → not observed. | — | Device controlled-day/pending delivery fixture and rotation policy; Native + product QA. |
| NOTIF-04 | P1 | Partial | Authorized settings persisted/read → API13 checks. | A 13/0 | Native fetching/local scheduling/delivery E2E; Native QA. |
| NOTIF-05 | P1 | Partial | Day/hour/minute bounds/missing schedule → API26 checks. | A 26/0 | Client missing-settings error presentation; Client QA. |
| NOTIF-06 | P0 | Blocked | Only own reminders queued → not observed. | — | Two-user Android assignment/pending queue inspection; Native + security QA. |
| NOTIF-07 | P1 | Blocked | Escalations/future-only/labels → not observed. | — | Native clock-controlled deadlines and all offsets; Native QA. |
| NOTIF-08 | P1 | Blocked | Past/deadline/escalation-disabled safe → not observed. | — | Controlled clock/illogical-settings fixtures and product policy; Native + product QA. |
| NOTIF-09 | P0 | Blocked | Completion/logout/leave/delete cancel → not observed. | — | Pending queue and account/group lifecycle on Android; Native + security QA. |
| NOTIF-10 | P1 | Blocked | Settings/reload/restart no duplicates → not observed. | — | Device process restart/ID cancellation fixture; Native QA. |
| NOTIF-11 | P1 | Blocked | Fetch-order independent schedule → not observed. | — | Delayed settings/assignment responses plus device queue; Native QA. |
| NOTIF-12 | P0 | Blocked | Intended timezone/DST delivery → not observed. | — | Android UTC/Kolkata/DST/Monday clock matrix; Native QA. |
| NOTIF-13 | P1 | Blocked | Idle/reboot/force-stop behavior disclosed → not observed. | — | Real Android OS battery/reboot limits matrix; Native QA. |
| NOTIF-14 | P1 | Blocked | Web unsupported state graceful → not observed for preferences. | — | Web/unsupported notification-plugin controls fixture; Client QA. |

### MEDIA — audio

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| MEDIA-01 | P1 | Blocked | Play/pause/resume/stop correct → no verified playback. | — | Reachable media host/user gesture/device; browser audio timeout inconclusive; Media QA. |
| MEDIA-02 | P1 | Blocked | Metadata/track coverage correct → not inspected by data runner. | — | Offered-track/5-aarti inventory and permitted media review; Media/content owner. |
| MEDIA-03 | P0 | Blocked | Combined/interior audio identity → not observed. | — | Real tracks/range/language playback matrix; Media/content QA. |
| MEDIA-04 | P1 | Blocked | Seek/speed/control bounds → not observed. | — | Playing track and duration/near-boundary gestures; Media QA. |
| MEDIA-05 | P1 | Blocked | Native download/cache offline plays → not observed. | — | Android storage/network/cache inspection fixture; Native/media QA. |
| MEDIA-06 | P1 | Blocked | Release-web player registration works → build alone insufficient. | — | Browser user-gesture streaming/plugin verification; Media QA. |
| MEDIA-07 | P1 | Blocked | Faulted download recoverable → not observed. | — |404/timeout/redirect/corrupt-partial media fixture; Media QA. |
| MEDIA-08 | P1 | Blocked | Low disk/interrupted cache safe → not observed. | — | Android low-storage/kill/cancel fixture; Native/media QA. |
| MEDIA-09 | P1 | Blocked | Switching player/mini-player consistent → not observed. | — | Simultaneous hub/reader audio and resource inspection; Media QA. |
| MEDIA-10 | P1 | Blocked | Background/interruption policy correct → not observed. | — | Android lock/Bluetooth/headphone/call fixture and policy; Native/media QA. |
| MEDIA-11 | P1 | Blocked | End/replay/rapid gestures no leak → not observed. | — | Repeat playing-session route/gesture stress fixture; Media QA. |
| MEDIA-12 | P1 | Blocked | Host failure/bandwidth graceful → not observed. | — | Controllable external URL/bandwidth/media outage; Media + DevOps QA. |

### LIVE / INFO — external and public information

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| LIVE-01 | P1 | Partial | Live route/player accessible → web iframe reached only. | E | Picture/sound/HLS upstream and Android playback not verified; Media QA. |
| LIVE-02 | P1 | Blocked | Upstream failure502/recovery → not executed. | — | Timeout/error/missing-newurl fixture and client; API + Media QA. |
| LIVE-03 | P1 | Blocked | Expired URL/network recovery → not observed. | — | Expired stream/refresh/renewal/network fixture; Media QA. |
| LIVE-04 | P1 | Blocked | Fullscreen/orientation/lifecycle → not observed. | — | Playing stream and native/browser control matrix; Media QA. |
| LIVE-05 | P1 | Blocked | Missing AAC fallback honest → not observed. | — | Codec-limited browser/Electron playback fixture; Media QA. |
| LIVE-06 | P1 | Blocked | HTTPS/origin/player reachable → not certified. | — | Production-like HTTPS/CORS/CSP/WebView deployment; DevOps + Media QA. |
| INFO-01 | P1 | Blocked | Events cache/empty/fault recovery → not observed. | — | Seeded empty/cached events and upstream-fault responses; API + Client QA. |
| INFO-02 | P1 | Blocked | Festival parser fixture correct → not executed. | — | Permitted HTML/date-variant/malformed/duplicate fixtures; API/content QA. |
| INFO-03 | P1 | Blocked | Startup/daily scrape no duplicates → not observed. | — | Real scheduled jobs, worker/restart fixtures; lifespan scraper was no-op; DevOps + API QA. |
| INFO-04 | P2 | Partial | Programme readable → temple opening/morning aarti schedule rendered. | E | Official external links/cancel/localization review; Content + Client QA. |
| INFO-05 | P1 | Partial | FAQ renders → guest questions visible. | E | Expand/collapse/search/all-language/offline matrix; Client QA. |
| INFO-06 | P1 | Blocked | All information remains public during outage → not observed as matrix. | — | Backend/media outage across all information screens; Client QA. |
| INFO-07 | P1 | Blocked | Festival refresh scope/throttle reviewed → not executed. | — | Authorized isolated refresh/upstream mock and product abuse policy; API + security QA. |

### LANG — localization/content review

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| LANG-01 | P1 | Partial | Codes/assets/flags agree →18 enum assets match; Urdu/beta source-inspected. | D,E | All17 selectable chooser interactions and flag visuals; Client QA. |
| LANG-02 | P1 | Blocked | Locale defaults/fallback correct → not observed. | — | Supported/unsupported OS locale fresh-install devices; Client QA. |
| LANG-03 | P0 | Blocked | UI/reader language independence persists → not observed. | — | Change/restart preference fixture per account/platform; Client QA. |
| LANG-04 | P1 | Blocked | Save/cancel/rapid switch coherent → not observed. | — | Real chooser/cancel/delayed-content race fixture; Client QA. |
| LANG-05 | P1 | Blocked | All screen labels understandable → not reviewer-tested. | — |17-language screen inventory and competent reviewers; Localization lead. |
| LANG-06 | P0 | Partial | No U+FFFD → all852 bodies/titles clear of replacement characters. | D,E | Native font/ligature/OCR/linguistic review; absence of U+FFFD insufficient; Localization lead. |
| LANG-07 | P1 | Blocked | Legacy Urdu/unknown preferences safe → not observed. | — | Seed legacy/invalid stored values and restart; Client QA. |
| LANG-08 | P1 | Blocked | Heading/passage boundaries correct → not source-reviewed. | — | Permitted originals and per-language chapter reviewers; Content lead. |

### A11Y — accessibility/layout

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| A11Y-01 | P1 | Blocked | Screen-reader labels/order usable → not observed. | — | Android TalkBack/web assistive tech critical-flow audit; Accessibility QA. |
| A11Y-02 | P1 | Blocked | Keyboard focus/dialogs usable → not observed. | — | Keyboard-only browser/dropdown/dialog matrix; Accessibility QA. |
| A11Y-03 | P1 | Blocked | Scaling/viewport no clipping → not observed as matrix. | — |100/150/200% text, landscape/tablet/small-screen runs; Accessibility QA. |
| A11Y-04 | P1 | Blocked | Contrast/noncolor status meets target → not measured. | — | WCAG2.2 AA contrast tooling/light-dark review; Accessibility QA. |
| A11Y-05 | P1 | Blocked | Targets/error/loading announcements → not observed. | — | Target measurement/assistive-tech form fixtures; Accessibility QA. |
| A11Y-06 | P1 | Blocked | Autofill/keyboard/safe area usable → not observed. | — | Real password manager/autofill/native navigation configurations; Accessibility QA. |
| A11Y-07 | P2 | Blocked | Reduced-motion/contrast/rotation safe → not observed. | — | OS accessibility settings plus modal/media rotation; Accessibility QA. |
| A11Y-08 | P1 | Blocked | Empty-state/task/destructive guidance → not observed. | — | Accessible user-task/reviewer fixtures and confirmations; UX/accessibility QA. |

### SEC — security/API contract

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| SEC-01 | P0 | Partial | Permissions authoritative →32 protected operations×5 roles plus denied-state fingerprints. | A 233/0 | Entire route inventory/parameter matrix/production DB review; Security QA. |
| SEC-02 | P0 | Fail | Object scoping subset passes; foreign cursor accepted200. | A 3/1,F10 | Assumed cursor rejection needs approval; **no body disclosure proved**; Security + API. |
| SEC-03 | P0 | Partial | Profile excludes credential/hash/OTP fields → API response subset. | A 2/0 | Other profiles/search/server logs/production PII inspection; Security QA. |
| SEC-04 | P0 | Blocked | Production HTTPS/storage/logs safe → not inspected. | — | Authorized release device/network capture/production-like logs; Security + DevOps. |
| SEC-05 | P0 | Fail | Invalid JWT subset rejected; replay/pre-change JWT200. | A 7/3,F01–03 | Known stateless revocation finding/signoff; exhaustive crypto review absent; Security + API. |
| SEC-06 | P1 | Partial | Malformed/null/types/no privilege mutation → API seven checks. | A 7/0 | Large-body/resource exhaustion/complete contract matrix; Security QA. |
| SEC-07 | P0 | Partial | Revoked membership/lead access denied → retained-session API checks. | A 21/0 | Actual open-reader/chat/manual-modal recovery; Client + security QA. |
| SEC-08 | P1 | Fail | Default wildcard permits untrusted preflight200,* in isolated loaded config. | A 1/1,F12 | Configuration safety failure; production allowlist/HTTPS not inspected; DevOps + security. |
| SEC-09 | P1 | Blocked | Concurrent identity/assignment/delete safe → not observed. | — | PostgreSQL concurrent unique/transaction fixtures; DB + Security QA. |
| SEC-10 | P0 | Blocked | Production multi-worker abuse controls → not observed. | — | Worker restart/multiple-workers/IP identifiers and approved policy; Security + DevOps. |
| SEC-11 | P1 | Partial | API literal text/no SQL mutation → two checks pass. | A 2/0 | Real rendering/avatar/resource/URL/XSS audit; Browser security QA. |
| SEC-12 | P0 | Blocked | Logout/delete/share no next-user leakage → not observed. | — | Device caches/downloads/reminders/share and approved retention policy; Security + Client QA. |

### RES — resilience/performance

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| RES-01 | P0 | Partial | API-down bundled reader works → English1 API-aborted web check. | E | Cold fully offline assets/cache/bookmarks/settings/information matrix; Client QA. |
| RES-02 | P1 | Blocked | Offline private actions/reconnect honest → not observed. | — | Network-fault E2E mutation/reconciliation fixture; Client QA. |
| RES-03 | P1 | Blocked | Commit/response-loss retry safe → not observed. | — | Post-commit dropped-response/retry capture fixture; API + Client QA. |
| RES-04 | P1 | Blocked | Network-switch loading recovers → not observed. | — | Wi-Fi/mobile/offline transition devices/fault proxy; Client QA. |
| RES-05 | P1 | Blocked | Async navigation/kill no leaks → not observed. | — | Device background/kill and delayed writes/player instrumentation; Client QA. |
| RES-06 | P1 | Blocked | Low-end startup/reader budgets → not measured. | — | Low-end target device, release build and **approved budget**; Performance + product owner. |
| RES-07 | P1 | Blocked | Large API capacity/query bounds → not measured. | — | PostgreSQL load dataset/concurrent users and **approved capacity budget**; DB/performance QA. |
| RES-08 | P1 | Blocked | Long media memory/battery/jank bounded → not measured. | — | Long-session Android instrumentation and **approved budget**; Native/performance QA. |
| RES-09 | P1 | Blocked | DB/upstream outage/recovery controlled → not executed. | — | Isolated DB restart/outage and controlled host latency; DevOps + API QA. |
| RES-10 | P1 | Blocked | Corrupt/full local storage recovers → not observed. | — | Preference/cache corruption and device storage faults; Client QA. |

### OPS — release/deployment

| ID | Priority | Result | Expected / actual subset observed | Evidence | Blocker or remaining scope; suggested owner |
|---|---|---|---|---|---|
| OPS-01 | P0 | Partial | Healthy/index unique → running API health, PostgreSQL mr53 unique read-only. | E,B | Isolated start/OpenAPI/restart/persistence sequence; DevOps + DB QA. |
| OPS-02 | P0 | Pass | DEBUG=false unsafe default refused; configured secret healthy → actual isolated lifespan. | E | None within isolated in-memory/no-op-scraper lifespan scope; no production deployment claim. |
| OPS-03 | P1 | Blocked | Effective target config precedence → not comprehensively verified. | — | Environment/CORS-array/API-URL target configurations; DevOps QA. |
| OPS-04 | P0 | Blocked | Schema/migration/backup restore → no rehearsal; alembic_version absent observed. | E observation only | Disposable PostgreSQL migration/backup/restore fixture; **not proof of data loss**; DB/DevOps. |
| OPS-05 | P0 | Partial | Release-web build/guest subset → JS build0, web guest smoke. | E,Q | Android release install/full smoke pack/HTTPS hosting; Release + Client QA. |
| OPS-06 | P1 | Blocked | Hosted deep links/device API reachability → not certified. | — | HTTPS SPA/API CORS deployment plus emulator/real Android; DevOps QA. |
| OPS-07 | P1 | Blocked | Upgrade/legacy cache/history compatible → not observed. | — | Prior-version install/preferences/schedules/audio fixtures; Release + Client QA. |
| OPS-08 | P1 | Fail | Suites pass but untriaged analyzer exit1 →378 info,0 warning,0 error. | B,F,Q,Q01 | Triage quality gate and execute dependency/security scan; Engineering lead + security. |
| OPS-09 | P0 | Blocked | Store/support claims match certification → not approved. | — | Release statement review against unsupported SMS/social/native/content scope; Release/product owner. |
| OPS-10 | P1 | Blocked | Cleanup/log redaction/rollback rehearsed → not observed. | — | Authorized isolated release rollback/restore and telemetry audit; DevOps + security. |

## 5. Exit criteria, caveats and next actions

**Exit criteria are not met.** Six P0 catalogue IDs fail, 71 P0 cases remain Partial and 21 P0 cases are Blocked. P1 execution/certification is also incomplete. Existing suites passing is necessary evidence, not sufficient release approval. There is no basis for declaring all 243 executed, a 100% manual pass rate, or production readiness.

1. API/client owners: fix and retest preview-confirm parity (F15/F16), tied-timestamp pagination (F09), controlled large-week handling (F04), and explicit cycle accounting (F05). Retest on PostgreSQL and real client flows, not only SQLite.
2. Security owner: decide retained JWT/replay lifetime/revocation and document AUTH-17/SEC-05 signoff or implement safety changes. Evaluate cross-group cursor semantics without inventing body-disclosure impact. DevOps/security must validate production CORS separately from the default isolated-config failure.
3. Product/reading lead: approve desired remainder allocations and ambiguous suggestion validation. SCH-10 runner oracles are provisional; SCH-15/16 acceptance findings require a defined contract. This does not waive unequivocal parity loss.
4. Client/native QA: complete Android release installs, reminder ownership/cancellation/timezone/DST/reboot/permission delivery, audio/download/background behavior, two-user account isolation, accessibility and offline cold/warm matrices. Audio/nonnumeric-route automation timeouts need explicit follow-up; they are not automatic failures.
5. DB/DevOps: provide disposable PostgreSQL concurrency, migration/backup/restore, worker/restart abuse controls and production-like HTTPS/storage/log/rollback environments. An absent migration marker alone cannot establish drift, corruption or data loss.
6. Content/localization lead: obtain permitted originals and competent-language reviewers. Nonempty JSON and no replacement characters do not establish correct passages, fonts, OCR, chapter boundaries or translations. Real SMS and verified social integration require independent implementation/configuration readiness, not fixture-based certification.
7. Engineering/release leads: triage 378 info-level analyzer findings, document quality-gate disposition, run a dependency/security scan, agree performance budgets, assign blockers and attach retest/signoff evidence. The 91 newer incompatible package versions are **not a vulnerability verdict**. Web Wasm dry-run and missing Cupertino font notices do not contradict the successful JavaScript build.

No defect was fixed and no policy approval was fabricated in this reporting task. Responsible owners and retest dates must be assigned by the project; the roles above are suggested ownership, not completed workflow records.
