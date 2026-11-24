# Android-first Firebase launch path

Date: 2026-10-13. This is a migration plan, not a production release approval.
Android is first; iPhone/iPad setup is deferred. The existing Flutter application
and FastAPI/PostgreSQL backend remain the working baseline.

## Cost boundaries: free tier is not the same as no billing

| Service | Initial decision |
|---|---|
| Local Emulator Suite | Use now; no cloud project or billing needed |
| Firebase Auth | Start with email/password on Spark; observe current quotas |
| Firestore Standard edition | Use Spark within its free quotas |
| FCM, Crashlytics, Remote Config | No-cost products; integrate later as needed |
| Cloud Functions | Production deployment requires Blaze/billing; not enabled now |
| Cloud Storage for Firebase | Requires Blaze/billing; do not move audio here now |
| SMS/phone authentication | Billed SMS; defer from the free-first launch scope |
| Google Play distribution | Developer registration has a one-time fee; not free |

Firestore free quota: one free database per project, 1 GiB stored, 50,000 reads,
20,000 writes and 20,000 deletes per day, plus 10 GiB outbound transfer per month.
Check current official terms before launch. Quotas, provider-specific Auth
limits and service eligibility still apply. Spark is not unlimited production
hosting, and quota exhaustion can interrupt service. Built-in Firestore backups,
PITR/restore and TTL deletion require billing.

Correction to the earlier broad migration proposal: deployed Functions and
Firebase Storage are **not available on a strict no-billing Spark setup**.
Blaze can include no-cost allowances but has charge exposure, including supporting
build/storage services. Budget alerts are notifications, not spending caps.

Keep bundled scripture, local bookmarks/reminders and existing audio hosting
unchanged for now. Existing media hosting is not a guaranteed free CDN: verify
distribution rights, provider terms, reliability and download volume.

Official references:
- [Firebase pricing](https://firebase.google.com/pricing)
- [Firestore free quotas](https://firebase.google.com/docs/firestore/quotas)
- [Firestore database locations](https://firebase.google.com/docs/firestore/locations)
- [Functions deployment billing requirement](https://firebase.google.com/docs/functions/get-started)
- [Storage billing requirement](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
- [Emulator setup](https://firebase.google.com/docs/emulator-suite/install_and_configure)

## Milestones and acceptance gates

### 1. Local foundation — implemented in this change

- Demo-only Auth/Firestore emulator configuration bound to loopback.
- Private user profile rules, deny-by-default for all unmigrated features.
- Repeatable emulator-only users and rule/Auth tests.
- Existing Flutter login/API and backend remain unchanged.

See [local setup](../firebase/README.md). No feature has been cut over yet.

### 2. Android identity and staging project — next

Confirmed owner decisions (2026-10-13):
- Existing accounts and history are test data; no legacy account/history import
  is required. Start Firebase with fresh accounts and disposable fixtures. Keep
  the existing local database during development; this is not an instruction to
  delete it now.
- Primary user country is India.

Recommended Firestore region: **asia-south1 (Mumbai)** for both staging and the
later production project. **asia-south2 (Delhi)** is another supported Indian
region; Mumbai is a proposed default, not a provisioned or approved resource.
Confirm the location before creating the database: it cannot be changed in place.
This location applies to Firestore, not a guarantee that all Firebase services
or authentication data are hosted in India. Spark free quotas still apply.

Android app name and final application ID are deferred by the owner. Continue
emulator-only backend work now; finalize the ID (currently com.example.om_sai_ram)
before Android Firebase registration or store publication. These are not
prerequisites for local rules, data-model or backend-contract development.

Owner creates a Spark staging project, with no billing upgrade, enables
email/password Auth and creates Firestore Standard edition in locked/production
mode. Later use a separate production project. Do not choose open test-mode
rules. Never put service-account credentials in Flutter or version control.

Add Android staging configuration only after the application ID/project are
confirmed. Emulator-only Flutter SDK integration can be designed separately.
Keep existing API as the default during
migration; explicit development configuration selects emulator or staging.
Release builds must reject emulator configuration. Do not silently fall back
from failed emulators to real services.

### 3. Authentication and profiles

Implement registration/login/logout, verified identity where required, password
reset, profile editing and coordinated account deletion. Create fresh Firebase
identities; password-hash imports, legacy UID mapping and password-reset
migration are unnecessary for the confirmed disposable data. Firebase string
UIDs and current PostgreSQL identifiers are still not interchangeable if a
temporary verified backend bridge is used.

Firebase tokens cannot be sent directly to the unchanged JWT API. Either move
dependent features together or build an explicit backend bridge that verifies
Firebase ID tokens server-side and enforces permissions. Never trust a UID
submitted by the client as proof of identity; no dual-login workaround based on
registering a supplied UID. Gate groups until a verified bridge exists.

Acceptance: Flutter unit/widget tests, emulator integration tests, negative
permission tests and physical Android staging tests all pass. Existing backend
test scenarios remain migration acceptance criteria, not automatically migrated
tests. User-visible account deletion must work across identity and related data.

### 4. Groups, assignments and progress — architecture gate

Initial emulator-only group slice implemented:
- Atomic group + creator/admin membership + owner discovery index creation.
- Member-only group/roster reads and owner-only group discovery, in pages of 50.
- Admin-added existing users, lead/member role changes and validated settings.
- Forged identity/role/orphan/index writes rejected by security rules.
- Additional admins, lead management, removals/deletion and week
  changes are intentionally blocked. No claim of full FastAPI feature parity.

Invitation follow-up: admin-only random tokens, default 24-hour expiry (maximum
seven days), one-way revocation and atomic authenticated self-joins are now
implemented locally. Tokens are multi-use bearer capabilities, not legacy
six-character codes. The Flutter join flow is not switched yet; see the
[invitation contract](../firebase/README.md#invitation-and-join-contract).

See the [group contract and remaining boundaries](../firebase/README.md#initial-group-backend-contract).
No Android identity is required for these local tests, and Flutter still uses
the current backend. Backend migration here means incremental replacement
contracts, not a production cutover.

Design group/member queries, invite handling, role changes, transaction
invariants, combined units, completion ownership and pagination before migration.

There are two options, requiring a decision before retiring FastAPI:
- **Strict no billing:** direct Firestore client operations with thoroughly tested
  security rules and transactions. Only workflows whose invariants can be
  enforced safely belong here. Client scheduling must never become trusted
  merely because its UI hides restricted actions. No trusted scheduled worker.
- **Full server-side feature parity:** trusted Functions for membership/admin
  operations, scheduling, deletion cleanup and external lookups. This requires
  Blaze or a separately hosted backend; cannot promise an entirely free service.

Keep the existing backend during development until this choice is validated.
Do not weaken roles or skip invite/uniqueness validation to fit Spark. Fix the
known scheduling defects before porting algorithms. Simultaneous clients and
forged writes must be tested, not just happy-path UI flows.

### 5. Chat, media and supporting features

Limit listeners to relevant groups and bounded recent messages; paginate with
a stable timestamp plus ID cursor. Model abuse controls, blocking/reporting and
retention. Measure document reads; small user counts alone do not guarantee
remaining below quotas.

FCM client delivery is no-cost, but automated sending needs a trusted server;
never embed sender credentials in the app. Preserve local reminders. Festivals
and live-stream lookup currently depend on the backend: choose cached/static
content, a safe replacement or an explicit first-release omission rather than
assuming Firestore replaces external processing.

### 6. Android beta and public release

- Resolve launch blockers in the [QA report](QA_TEST_REPORT_2026-10-13.md).
- Verify HTTPS, permission enforcement, recovery/data retention and quota behaviour.
- Test signed release builds on real Android devices (offline reader, audio,
  interruptions, downloads, notifications, accessibility and text scaling).
- Configure final icons, signing, Play App Signing and current target SDK.
- Prepare privacy policy, Data safety disclosures, support contact, account
  deletion and chat moderation/reporting. Verify scripture/audio usage rights.
- Use internal testing, then any required closed testing before production.
  Google Play account-specific verification/testing requirements apply.
- Rehearse fresh-start cutover/rollback; retire PostgreSQL only after acceptance.
  No legacy test-history import is required. Do not delete the old database
  prematurely; preserve any real beta data created after this decision.

## Current boundary

This first change prepares free local development only. It does not change
Flutter login, create Google accounts/projects, enable billing, deploy rules,
publish Android builds, stage/commit changes or migrate existing records.

## Initial validation — 2026-10-13

| Check | Result |
|---|---|
| Firebase Auth/profile/security/guard/seed suite | 16 tests passed |
| Existing Flutter unit/widget suite | 18 tests passed |
| Local fixtures seeded twice | Stable UIDs and creation timestamps verified |
| Cloud deployment or billing | Not performed |
| npm dependency audit after non-breaking fixes | 16 transitive development findings remain; see local setup notes |

Tested with Node 25.1.0 and a user-local Java 21 runtime. Prefer Node 22/24 LTS
for reproducible development: a transitive CLI package warns that Node 25 is not
in its supported engine list. No Android release build or production Firebase
behaviour has been certified by these checks.

### Group slice follow-up — 2026-10-13

Full emulator suite: **34 tests passed**, including 18 new group tests covering
atomicity, roles, privacy, invalid settings, forged writes and bounded queries.
No Flutter/FastAPI source changes or cloud deployment in this follow-up. Next
backend work: design invitation/join semantics, public member display data and
assignment/progress invariants before adding their permissions.

### Invitation slice follow-up — 2026-10-13

Full local suite: **49 tests passed** (34 prior tests plus 15 invitation tests).
The CLI reported successful test execution and emulator shutdown, but its
remaining process stalled afterward and was manually terminated. This is a
local-tooling caveat, not an Android or production certification result.

Added invitation creation/revocation, self-join and negative tests for expiry,
UID/role/group forgery, orphaned writes, privacy, immutable fields, duplicate
joins and revocation races. Authenticated exact-token lookup only; no invitation
collection listing, jobs, cloud resources or billing. Next backend slice is
manual assignments and assignee-owned progress, including combined chapter
units and duplicate prevention; automatic scheduling remains a separate gate.

### Further backend slices — 2026-10-13

Full emulator suite: **138 tests passed, exit 0**; no remaining emulator processes.
Incremental local contracts now include:
- Manual assignments with rule-enforced canonical combined units and deterministic
  uniqueness per member/week/unit; admin/lead creation and assignee-owned progress.
- Member-only chat with stable timestamp/document-ID pagination.
- Opt-in group-visible member names without exposing private profiles.
- Chapter highlights and quotes, with immutable authored records.
- Owner reminder preferences with validated India-first time settings.

See [contract details and limitations](../firebase/README.md#additional-local-backend-contracts).
No cloud deployment, billing, Flutter migration or existing-database deletion.
Audio remains on the existing GitHub Releases host.

Remaining gates, in implementation order:
1. Remaining scheduling policy decisions (Saptah and unsupported remainders),
  global assignment discovery/summaries and larger-plan coordination. Chapter-wise
  local scheduling and week advancement are now verified as described below.
2. Membership restore/rejoin policy, ownership policies, coordinated account/group cleanup,
  retention, moderation, reporting and blocking. Do not enable deletes partially.
3. Festivals/live-stream processing and actual reminder scheduling/push sending;
  choose safe no-billing alternatives or explicitly approve a trusted host/Blaze.
4. Flutter Firebase Auth and repository integration, errors/offline behaviour,
  long-token invitation UI, composite indexes and complete integration tests.
5. Owner-created staging/production project, database location approval, Android
  identity, signing and real-device beta/store certification.

No agent can run indefinitely after its session ends. These milestones are
completed work in the current session, not a persistent background service.

### Scheduling verification — 2026-10-13

The existing local scheduling module now has 40 dedicated tests. Full emulator
suite: **178 passed, 0 failed, exit 0**; emulators exited normally.
Four chapter-wise modes, validated hints, canonical units, explicit remainder
reporting, transaction duplicate/staleness handling and admin-only +1 advancement
were exercised, including concurrent commits/advancement and forged requests.

See [scheduling limits](../firebase/README.md#scheduling-and-week-advancement).
This does not certify Saptah, extend_last/round_robin, arbitrary large plans,
trusted server computation, complete FastAPI parity or Flutter integration.
Nothing was deployed or billed. The next safe local slice is membership lifecycle
and coordinated access revocation; destructive cleanup must not be enabled without
an explicit complete-data retention/deletion design.

### Membership lifecycle — 2026-10-13

Full emulator suite: **220 passed, exit 0**, including 42 new lifecycle tests.
Self-leave, admin removal and lead removal of ordinary members now atomically
revoke membership/discovery and remove shared display profiles, with immutable
departure audit records. Creator immunity, forged/partial writes, role checks,
concurrent operations, revoked access and retained history were tested.

History is not erased. Rejoin/admin re-add is blocked after departure until
trusted cleanup or membership generations are implemented; this intentionally
differs from the old backend and needs release-policy approval. Account/group
deletion, moderation and retention cleanup are still pending. See the
[lifecycle contract](../firebase/README.md#membership-lifecycle-and-retention).
No Flutter/backend cutover, cloud deployment, billing, staging or commit.

### Reporting and moderation — 2026-10-13

Full emulator suite: **278 passed, exit 0**, including 58 new tests. Current
members can report messages/highlights; admins can resolve reports and atomically
remove content with immutable minimal audit records. Tests cover identity/role
forgery, partial deletes, ID reuse, retained reports, pagination and races.

See [moderation limits](../firebase/README.md#reporting-and-moderation).
This supersedes the prior blanket content-delete prohibition: uncoordinated
deletion remains forbidden, but audited admin deletion is now allowed.
Blocking, moderation UI/global queues, automated filtering, retention purge,
account/group deletion and complete production policy validation remain pending.
No cloud deployment/billing or Flutter/FastAPI changes.

### Own assignment discovery — 2026-10-13

Full emulator suite: **299 passed, exit 0**, including 21 discovery tests.
The local client now pages through the user's private group index and reads
their assignments with per-week status summaries. Defaults are five groups and
one current week; limits are ten groups and three weeks. Explicit week selection
supports history. Other-user indexes, stale revoked access and global queries
remain denied; failures never silently return partial results.

See [discovery limits](../firebase/README.md#assignment-discovery) for pagination,
non-atomic read behavior and document-based billing. This adds bounded own-task
aggregation, not global/group-wide summaries or Flutter dashboard integration.
No rule expansion, cloud deployment, billing or Flutter/FastAPI changes.

### Flutter Firebase authentication integration — 2026-10-13

Flutter now supports an isolated optional Firebase emulator mode; earlier
milestones stating no Flutter integration apply to their historical snapshots.
FastAPI is still the default full app. Firebase mode offers actual email/password
signup/login/logout, SDK-managed restoration and exact private Firestore profiles
with retryable setup. It blocks all legacy API requests and does not instantiate
legacy auth/navigation; group and reading workflows are still pending integration.

See [mode and connectivity instructions](../om_sai_ram/README.md#firebase-emulator-authentication-mode).
Android/web debug only, pinned demo project, no cloud fallback, no paid SMS,
social login or account deletion. Web requires a localhost page for the current
FlutterFire emulator restoration hook. Dependency upgrades must revalidate it;
the app lockfile is now eligible for version control.

Validation: **53 Flutter tests passed** (35 new), analyzer zero warnings/errors
with 378 existing infos, Firebase debug web and Android APK builds passed.
Browser/emulator checks verified signup, session restoration, login/logout and
missing-profile repair without live Firebase/legacy API requests. Android
real-device auth, release signing/identity and store certification remain pending.
No cloud deployment, billing, staging or commit.

### Flutter Firebase groups — implementation complete, validation pending

The emulator-only workspace now connects atomic group creation and invitation
joining, own-index pagination, member rosters and admin invitation issuance/
revocation. Routes require a ready Firebase profile; actual membership roles
control invite UI and rules independently enforce permissions. UID-bound state
discards delayed responses after session changes. No legacy API/shell is used.

Android debug APK and Firebase debug web builds passed. Flutter results are
**82 passed / 1 failed out of 83**, including the unchanged passing 53-test
baseline. The remaining test cannot find a lazily unmounted Refresh button after
scrolling; the test-fix retry limit was reached. Analyzer reports 379 infos,
including one new unnecessary test import, with no warnings/errors.

Browser group integration was **not verified**: localhost access from the shared
browser returned connection refused although the development terminal received
HTTP 200. Privately forwarded web/Auth/Firestore ports are required to resume.
Only validation-owned servers were stopped. See
[workflow boundaries](../om_sai_ram/README.md#firebase-groups-validation-in-progress).
Do not claim end-to-end success or release readiness. No cloud deployment,
billing, staging or commit. Assignments/reader integration remains next work.

### Flutter manual assignments and progress — 2026-10-14

The prior group scroll-test failure is repaired with all assertions preserved;
all 83 baseline tests pass. The isolated Firebase workspace now has a guarded
Assignments screen per group, selected member/week server reads, canonical
48-unit manual assignment creation for actual admins/leads, and assignee-only
status controls. Dates are explicitly null/Unscheduled; writes reload server data.
Duplicate transactions do not overwrite, and session/member/week changes discard
stale responses. No legacy API or SQL chapter IDs are used.

Full Flutter suite: **148 passed**, including 65 new tests. Analyzer: 378 existing
infos, zero warnings/errors. Firebase Android debug APK and web debug builds pass.
These tests use SDK-shaped doubles; actual Flutter SDK/emulator transactions,
concurrency and group/assignment end-to-end flows have not been certified.
The prior browser forwarding limitation remains a validation gate.

See [assignment boundaries](../om_sai_ram/README.md#firebase-manual-assignments-and-progress).
Reader launch/completion, automatic scheduling, cross-group dashboard, scheduled
date selection and remaining community features still require Flutter integration.
FastAPI is still the default. No cloud deployment, billing, staging or commit.

### Firebase assignment reader and completion — 2026-10-14

Assignment cards now open a guarded bundled-only reader for the exact group,
assignee, week and canonical unit. Fresh server assignment access is required;
invalid links and missing/denied assignments do not expose local content through
this workflow. Content loading reuses range assembly/translation fallback without
constructing the legacy API client. The old FastAPI reader remains unchanged.

Only the signed-in assignee can explicitly mark completion, and confirmation
requires a server reload showing Completed. Opening/scrolling does not write
progress. Back navigation refreshes the exact assignment scope. Language/font
preferences are installation-wide; audio, bookmarks/history, search and chat
announcements are not connected in the isolated Firebase reader.

Full Flutter suite: **196 passed** (48 new). Analyzer: 378 existing infos, zero
warnings/errors; infos still cause exit 1. Firebase debug web and Android APK
builds pass. Tests include bundled-content checks but use gateway doubles for
Firestore; real SDK/emulator flows and Android device QA remain pending.
See [reader boundaries](../om_sai_ram/README.md#firebase-assignment-reader-and-completion).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter My reading tasks dashboard — 2026-10-14

The guarded Firebase workspace now discovers the signed-in user's assignments
across groups using the private index, bounded sequential server reads and strict
models. Defaults: five groups/page, one current week per group. Up to three weeks
or an explicit historical start week are supported. Empty groups/weeks remain
visible; next-page replaces the page. Counts are user/page/week-scoped only.
Reader links preserve exact member/week/unit and refresh the same page on return.

Full Flutter suite: **242 passed** (46 new); analyzer: 378 existing infos, zero
warnings/errors. Firebase Android APK and web debug builds pass. Tests use
controlled SDK-shaped doubles; real SDK/emulator/rules and device checks remain
pending. No polling, aggregate writes, roster/other-private-profile discovery or
global collection-group query. Document bounds are not billing caps.
See [dashboard limits](../om_sai_ram/README.md#firebase-my-reading-tasks-dashboard).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter group chat and member reporting — 2026-10-14

Group detail now opens guarded Firebase chat with sequential server-only history,
default 20/max 50 messages, full-precision timestamp/document-ID cursors, member
message sending and transactional one-report-per-user/message submission. UID
display avoids private identity copies. Permission/error/session changes clear
old data; uncertain auto-ID writes are not automatically retried. Acknowledged
sends refresh the newest page and clear the draft even when refresh fails.

Full Flutter suite: **336 passed** (94 new). Analyzer: 378 existing infos, zero
warnings/errors. Firebase Android APK and web debug builds pass. Gateway doubles
do not certify actual SDK/rules integration; real emulator/device validation is
still pending. Moderator review/resolution/removal, blocking, retention cleanup,
highlights and completion announcements are not connected in this UI.
See [chat boundaries](../om_sai_ram/README.md#firebase-group-chat-and-reporting).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter message-scoped admin moderation — 2026-10-14

Actual admins can review paginated reports for an individual chat message,
resolve/dismiss open reports once, and confirm removal with a reason. Removal
atomically writes a minimal immutable audit and deletes the target; reports
remain retained and removed IDs cannot be reused. Session/permission failures
clear stale data. Acknowledged writes are distinguished from reload failures,
and returning to chat refreshes the head. No text/private identity copies in audits.

Full Flutter suite: **434 passed** (98 new); analyzer: 378 existing infos, zero
warnings/errors. Firebase debug web and Android APK builds pass. Tests use
controlled SDK-shaped doubles; actual SDK/rules/emulator/device validation is
still pending. Global report queues, highlights moderation, blocking, filtering,
retention cleanup and account/group erasure remain separate work.
See [moderation boundaries](../om_sai_ram/README.md#firebase-message-moderation).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter group highlights and reporting — 2026-10-14

Members can now share and browse highlights through a guarded group route, with
original chapters 1–53, explicit paragraph anchors and manually supplied quote/
comment fields. Anchors/quotes are not verified against scripture or a content
version. Server-only pages preserve timestamp nanoseconds, default 20/max 50,
replace older pages and fail as a whole. SDK identities/server timestamps and
acknowledged-versus-uncertain delivery behavior avoid optimistic claims/retries.
Transactional member reports reject duplicates/unavailable targets.

Full Flutter suite: **593 passed** (159 new); analyzer: 378 existing infos, zero
warnings/errors. Firebase debug Android APK and web builds pass. Real SDK/emulator
and device end-to-end verification remains pending; test doubles are not server
certification. Highlight moderation and reader-selection sharing remain pending;
existing moderation UI still handles messages only. No rule/backend changes.
See [highlight boundaries](../om_sai_ram/README.md#firebase-group-highlights).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter highlight admin moderation — 2026-10-14

Shared moderation now uses explicit message/highlight kinds with isolated paths,
state and schemas. Actual admins can review highlight reports, resolve/dismiss
them once, and remove highlights through a confirmed atomic minimal-audit/delete
transaction. Original message routes/defaults remain compatible. Highlight preview
anchors/quotes stay explicitly unverified; reports remain under deleted targets.
Returning from moderation refreshes newest highlights; permission/session failures
clear stale data. No quote/comment copies are retained in the audit.

Full Flutter suite: **702 passed** (109 new; existing 98 message-moderation tests
preserved). Analyzer: 378 existing infos, zero warnings/errors. Firebase debug
web and Android APK builds pass. No live SDK/emulator/device runtime validation;
SDK doubles are not proof of transport, rules or server transaction guarantees.
Global queues, blocking, filtering, retention purge and account erasure remain
pending. See [highlight moderation limits](../om_sai_ram/README.md#firebase-highlight-moderation).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter group departure and member removal — 2026-10-14

Confirmed self-leave and authorized member removal now connect to the canonical
Firebase lifecycle transaction: minimal immutable departure marker, membership,
private discovery index and optional shared-display deletion. Actual roles and
creator immunity are checked on transaction retries. No other-user private index
reads, partial cleanup or history deletes. UID-bound confirmations disclose retained
history and the current indefinite rejoin/add restriction before proceeding.

Write acknowledgements are separate from reload failures; self-leave returns to
groups and removal refreshes the roster/invalidate session-dependent local data.
This is access revocation, not account/group deletion, erasure or remote cache
removal. Ownership transfer, cleanup/versioning and safe rejoining remain pending.

Full Flutter suite: **815 passed** (113 new). Analyzer: 378 existing infos, zero
errors/warnings. Firebase web and Android APK debug builds pass. SDK-shaped doubles
are not live rules/SDK/device certification. See
[lifecycle limits](../om_sai_ram/README.md#firebase-group-departure-and-member-removal).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter group settings and lead roles — 2026-10-14

Actual admins can now edit group name/description and chapter-wise width/start,
and promote members to group lead or demote leads. Transactions revalidate roles,
protect creator/self/admin targets and reject stale settings with exact raw
updatedAt timestamp comparisons. Settings do not reschedule assignments or
advance the week. Saptah edits are restricted to name/description in this UI.

UID-bound confirmations/forms discard stale responses; successful changes
invalidate affected local permission state and refresh data. Acknowledgements
are distinguished from reload failures. Extra admins/ownership transfer remain
unsupported; role changes are not guaranteed live pushes to other clients.

Full Flutter suite: **991 passed** (176 new). Analyzer: 378 existing infos, zero
warnings/errors. Firebase web and Android APK debug builds pass. No live SDK/
rules/device validation; SDK-shaped transaction tests are not server guarantees.
See [administration limits](../om_sai_ram/README.md#firebase-group-settings-and-lead-roles).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter opt-in group display names — 2026-10-14

Members can explicitly publish/change a group-visible name and browse the bounded
published-name directory. No private name/email copying, roster backfill or name
snapshots. UID remains the authorization identity and is shown beside unverified,
nonunique names. Transactions revalidate membership, preserve raw creation time
and set server update time. UID-bound confirmations disclose that unpublish is
not supported; departure removes shared display data but cannot erase downloads.

Full Flutter suite: **1,143 passed** (152 new); analyzer: 378 existing infos, zero
errors/warnings. Firebase debug web and Android APK builds pass. Gateway doubles
do not certify live SDK/rules/device behavior. Directory pages default 20/max 50;
roster/chat/highlights still display UIDs without name lookup fan-out.
See [display-name limits](../om_sai_ram/README.md#firebase-opt-in-group-display-names).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter personal reminder preferences — 2026-10-14

Ready Firebase sessions can load/save their own reminder preferences through the
workspace or `/reminders`. Missing settings remain absent with unsaved off/off
09:00 Asia/Kolkata defaults. Both toggles use one shared India time. Exact-schema
full replacement writes add server `updatedAt`; reads are server-only. Account
switches discard delayed results; uncertain saves require explicit server
verification before another write, with acknowledged reload failures distinct.

**Storage only:** no OS notification permissions, scheduling, device tokens,
FCM, Functions or delivery guarantees. Existing FastAPI-mode reminders are not
invoked. Full Flutter suite: **1,303 passed** (160 new); analyzer: 378 existing
infos, zero errors/warnings. Firebase debug web and Android APK builds pass.
SDK-shaped doubles do not certify live SDK/rules/device behavior.
See [reminder limits](../om_sai_ram/README.md#firebase-personal-reminder-preferences).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter bounded automatic scheduling — 2026-10-14

Admins/leads can preview four chapter-wise modes over an explicitly ordered
member subset, then confirm create-only atomic assignments. Manual/truncate/cycle
remainders expose unfilled slots. Preview limits: 50 members, 12 weeks including
current, 4,096 requested slots; commit limits: 1–48 writes and 12 target members.
Transactions reread settings/roles/memberships and reject any existing assignment;
all reads precede writes. No hidden chunking, skips, overwrite or whole-roster claim.

Admin-only week advancement is separately confirmed, transaction-current +1,
capped at 10,000, with no scheduling side effects. Unverified outcomes require
explicit server-head verification and a new confirmation, never blind retry.
Saptah scheduling and hint suggestions remain unsupported; UI dates are null
Unscheduled. No implicit calendar, background jobs or notification delivery.

Full Flutter suite: **1,579 passed** (276 new); analyzer: 378 existing infos,
zero errors/warnings. Firebase debug web and Android APK builds pass. SDK-shaped
doubles do not certify live SDK/rules/device behavior; rules authorize assignments,
not formula correctness. See [scheduling limits](../om_sai_ram/README.md#firebase-automatic-scheduling-and-week-advancement).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter chapter-hint suggestions — 2026-10-15

Selected UID-bound hints now generate reviewable schedule suggestions using
canonical-unit normalization, actual position gaps and consistency across every
hint. Supported inferred patterns are synchronized, rotating window and dense
window; one week's independent/rotating ambiguity is disclosed. Invalid/custom
steps are rejected. Reordering preserves UID hints; removing a selection removes
only its hint. Suggestions reload settings/roles and edits invalidate previews.

No writes occur until existing explicit atomic confirmation. The same 50-member,
12-week, 4,096-slot preview and 48-write/12-target commit bounds remain. UI dates
remain Unscheduled; Saptah scheduling remains unsupported.

Full Flutter suite: **1,663 passed** (84 new); analyzer: 378 existing infos,
zero errors/warnings. Firebase debug web and Android APK builds pass. SDK-shaped
doubles do not certify live SDK/rules/device behavior.
See [suggestion limits](../om_sai_ram/README.md#firebase-pattern-suggestions).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter private account and reset requests — 2026-10-15

Ready sessions can edit private profile names through `/account`. Exact-schema
server reads and name-only transactions preserve creation timestamp precision;
missing profiles are not created. Group display names and Auth identity fields
remain unchanged. Workspace names refresh only through confirmed server data.
Account-bound drafts/results distinguish acknowledgment from reload failure.

Logged-out `/forgot-password` requests use Firebase Auth directly, return generic
account-neutral success and never read Firestore or retrieve/log reset codes.
Auth emulator requests do not send real email; delivery remains staging QA.
Signed-in reset, email/password changes, verification and erasure are deferred.

Full Flutter suite: **1,821 passed** (158 new); analyzer: 378 existing infos,
zero errors/warnings. Firebase debug web and Android APK builds pass. SDK-shaped
doubles do not certify live SDK/rules/device behavior.
See [account limits](../om_sai_ram/README.md#firebase-private-account-and-password-reset).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter reauthenticated password changes — 2026-10-15

Ready sessions with a linked password provider can explicitly reauthenticate
using their current password and update it through `/account/change-password`.
The SDK account supplies identity; no hidden sign-in, Firestore/profile access,
legacy API or credential persistence is involved. Password fields clear on
submission/completion/session change/disposal; safe errors do not expose SDK text.

Post-dispatch failures are uncertain and block retries across route reopening
until session change. Users must log out and verify login/reset explicitly.
Already-dispatched updates cannot be undone; secure memory zeroing and revocation
of other sessions are not claimed or implemented.

Full Flutter suite: **1,895 passed** (74 new); analyzer: 378 existing infos,
zero errors/warnings. Firebase debug web and Android APK builds pass. SDK-shaped
doubles do not certify live SDK/emulator/device behavior.
See [password limits](../om_sai_ram/README.md#firebase-password-changes).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter reader selected-text highlights — 2026-10-15

The assignment reader now offers explicit selected-text review and group sharing.
Exact quotes and actual source/fallback language are retained; source-aware
chapter choices and user-supplied paragraph anchors remain explicitly unverified.
Assignment access is rechecked before review and sending. Selection/language/
content/session changes discard stale work; sharing never changes progress.

Acknowledgment is distinct from refresh failure. Uncertain auto-ID writes require
explicit server-head verification before a new send; a bounded page cannot prove
non-delivery. Guards are memory-only, with no persisted drafts or restart guarantee.
No automatic sharing, legacy API or Firestore contract changes.

Full Flutter suite: **1,929 passed** (34 new); analyzer: 378 existing infos,
zero errors/warnings. Firebase debug web and Android APK builds pass. SDK-shaped
doubles do not certify live SDK/rules/device behavior.
See [reader-sharing limits](../om_sai_ram/README.md#firebase-reader-highlight-sharing).
No deployment, billing, staging or commit; FastAPI remains the default.

### Flutter standalone bundled reading — 2026-10-15

Guests and members can open Read Satcharita without an assignment. Public reader
routes accept strict original numbers 1–53, preserve actual merged translations
and separate Marathi originals, and disclose fallback content. Search, original
chapter navigation, language/font preferences, RTL and local retry are connected.
No reading-triggered API, profile, Firestore, progress or notification calls.

Protected group routes remain unchanged. Bundled text works offline after startup,
not a claim of fully offline Firebase boot; named emulator bootstrap still applies.
Standalone audio, bookmarks, history and highlight sharing remain deferred.

Full Flutter suite: **1,968 passed** (39 new); analyzer: 378 existing infos,
zero errors/warnings. Firebase debug web and Android APK builds pass. Live SDK/
emulator/device certification remains pending.
See [standalone limits](../om_sai_ram/README.md#firebase-standalone-bundled-reading).
No deployment, billing, staging or commit; FastAPI remains the default.

### Launch scope and release readiness — 2026-11-22

The owner approved the launch scope: app name **Om Sai Sannidhi**; email,
Google, phone and Apple sign-in; permanent account deletion; a production
Firebase mode; and Firebase as the default backend. This section supersedes the
"FastAPI remains the default", "debug only" and "account deletion not
implemented" statements in the dated sections above.

- **Default backend:** Firebase on Android and web. A debug build uses the local
  emulators; a build given a real project never touches an emulator; a release
  without a project stops with an explanatory message. FastAPI stays available
  with `BACKEND_MODE=fastapi` and is the default on desktop and iOS.
- **Sign-in:** Google, Apple and phone are connected with explicit linking. The
  app never matches or merges accounts by email. Phone SMS and deployed feed
  Functions still need the Blaze plan, as stated in the cost table above.
- **Account lifecycle:** ownership transfer, reversible deactivation and
  permanent deletion. Deletion removes the sign-in, private profile and
  reminder preferences and leaves every writable group; content already shared
  stays under an anonymous UID. It is blocked while the account owns a group and
  refused before any removal when the sign-in is older than five minutes.
- **Scheduling:** Weekly Saptah is a group label that shares weekly scheduling;
  `extend_last` and `round_robin` finish the book in the last planned week.
- **Release plumbing:** upload-key signing through `android/key.properties`,
  Hosting config for the web build, and privacy and account-deletion pages.

Verified: **2,368 Flutter tests**, **379 emulator tests**, 75 Functions tests,
debug and release web builds, debug and release APK builds. Release builds used
placeholder project identifiers and the debug signing fallback.

Not done, and required before publishing: everything in the
[launch checklist](LAUNCH_CHECKLIST.md). Nothing has run against a real Firebase
project or a physical device, no rules were deployed, and the application ID is
still `com.example.om_sai_ram`. The Firebase screens keep their development
wording and layout until the planned UI pass. No commit or push was made.
