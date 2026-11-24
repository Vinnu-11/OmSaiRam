# Local Firebase foundation

Local foundation plus groups and invitations: Auth and Firestore emulators,
private profile/group rules, local fixtures and automated tests.
**Flutter still uses FastAPI/PostgreSQL.** No production
project, cloud resource, billing account or Flutter Firebase configuration is
created by this setup. See the [Android launch plan](../docs/FIREBASE_ANDROID_LAUNCH.md).

## Requirements and entry points

- Node.js 22 or newer (prefer a supported LTS release), npm, Java 21 or newer on
  PATH. The pinned Firebase CLI requires Java 21 for the Firestore emulator.
- On the initial Linux development host, a user-local Java 21 runtime was installed
  under $HOME/.local/share/om-sai-ram-java21. The emulator launcher uses it when
  JAVA_HOME is unset; this does not change the Android build's Java installation.
  Other machines must supply Java 21+; the launcher fails clearly if unavailable.
- Install this directory's dependencies using npm install, or npm ci once the
  lockfile is present. All commands below refer to npm scripts in this directory;
  from the repository root, use npm's `--prefix firebase` option.
- `npm run emulators`: start Auth, Firestore and the local UI.
- `npm run emulators:functions`: start the separate Functions-only runtime under
  Node 22; see the trusted-feed section below before starting it.
- `npm run seed`: create/update the two fixture profiles while emulators run.
- `npm run test:unit`: validate safety guards without Java/emulators.
- `npm test`: start fresh emulators, run the full suite, then shut them down.
  Stop any manually running emulators before using this command. Tests clear
  local Firestore documents; never run against a fixture session you want to keep.

The first emulator run downloads binaries from Google. There is no Firebase
login, service-account key or credit card requirement for these demo emulators.
Do not use firebase init to overwrite this setup or run a cloud deploy yet.

## Endpoints

| Service | Loopback endpoint |
|---|---|
| UI | http://127.0.0.1:4000 |
| Auth | 127.0.0.1:9099 |
| Firestore | 127.0.0.1:8085 |
| Functions (separate launcher) | 127.0.0.1:5001 |
| Project ID | demo-om-sai-ram |

Firestore uses 8085 rather than its usual 8080 to avoid common development-server
conflicts. All scripts pin the demo project; they refuse conflicting project
environment variables and nonmatching emulator endpoints. The seeder connects
both client SDKs to emulators before any request and fails if unavailable.

Fixtures are disposable, not production users:

| Email | Password | Profile |
|---|---|---|
| reader.one@example.test | LocalDemo123! | Local Reader One |
| reader.two@example.test | LocalDemo123! | Local Reader Two |

Seeding twice preserves each UID and creation timestamp. It does not copy or
delete existing PostgreSQL records. There are no Firebase group/admin fixtures
yet; group workflows are exercised through isolated automated tests instead.

## Profile contract and security

Only users/{Firebase UID} is currently allowed, with exactly displayName,
createdAt and updatedAt. Owners can get/create/update their own profile. Queries
over all profiles, other users' access, direct profile deletion and extra fields
(including roles) are denied. Timestamps use serverTimestamp; createdAt is
immutable. Email/password identity remains in Firebase Auth, not Firestore.

Account deletion needs a coordinated implementation before release; the Auth
smoke test is not proof of end-to-end application deletion. Apart from the group
paths described below, other document paths are locked. These are incremental
contracts, not final rules for the whole app.

## Initial group backend contract

The [group client contract](src/groups.mjs) uses the standard Firestore client
SDK and write batches, not an Admin SDK that bypasses rules. It is a JavaScript
reference implementation for tests; the Flutter repository is not migrated yet.

| Path | Contract |
|---|---|
| groups/{id} | Group settings; only members can get, no global list |
| groups/{id}/members/{uid} | userId, role, joinedAt; group members can read |
| users/{uid}/groups/{id} | Private owner-readable groupId/joinedAt discovery index |

Invite-based joins also store inviteToken in the joining user's private discovery
index for rule validation. It is never stored in the group or public roster.

- createGroup writes group + creator admin membership + discovery in one batch.
  Each path validates the other post-write documents; partial bootstraps fail.
- Creator must already have a private profile. Group starts at week 1, with
  chaptersPerWeek 2/startChapter 1 by default. Names are nonblank, at most 100
  characters; descriptions at most 1000; chapter settings are integers 1–53.
- Admin can add an existing profile UID as member; membership and target user's
  discovery index are written atomically. Duplicate adds fail; no reset/overwrite.
- Only admin changes settings and noncreator roles between member/group_lead.
  Additional admins, ownership transfer and creator demotion are blocked.
- Leads can assign readings and remove ordinary members; invitation issuance,
  adding members and role/settings changes remain admin-only. Member records
  deliberately do not copy private names/emails.
- listMyGroups and listMembers return up to 50 rows ordered by document ID.
  Pass the last returned ID as afterId for the next page. Rules reject unbounded
  or over-50 queries. A page is not a complete group/member listing.
- User lookup, account/group deletion and member count aggregation are not
  implemented here. Do not enable those Flutter flows against this contract.
- Discovery is not authorization: canonical group membership grants access.
  Adding by UID mirrors the existing admin flow; consent/invitation policy still
  needs review before production. Rules tests use simulated identities and do
  not establish production abuse protection or complete release certification.

Validation: 34 local tests passed after this slice (18 group tests plus the
16 foundation tests). Existing backend and Flutter files were not changed.

## Invitation and join contract

The [invitation reference client](src/invitations.mjs) adds createInvitation,
revokeInvitation and joinWithInvitation. These are emulator-tested Firestore
operations, not deployed API endpoints or Flutter UI integrations.

- Only the group admin creates/revokes invitations. Leads may remove ordinary
  members through the separate lifecycle contract but cannot issue invitations.
- Tokens use 32 CSPRNG bytes encoded as 64 lowercase hexadecimal characters.
  The client generates entropy; rules validate format/permissions, not randomness.
  Do not log, expose in analytics, or publish these bearer capabilities.
- groupInvites/{token} holds groupId, createdBy, createdAt, expiresAt and active.
  Authenticated users can get a known token; nobody can list invites. Knowing
  a token reveals that record, even after revocation/expiry; it grants no group
  read permission before joining. Never allow collection scanning for lookup.
- Tokens are multi-use (any signed-in holder with a profile may join), valid for
  24 hours by default and at most seven days. This intentionally replaces legacy
  permanent six-character codes. It is not a one-recipient invitation or a group
  approval workflow. Review this policy before production.
- Expiry is enforced with server time by security rules, not a trusted client
  clock. Revocation is one-way; group/creator/expiry are immutable. To renew or
  rotate, create a new token and explicitly revoke old ones as needed.
- A join creates membership and private discovery in one atomic batch; rules
  revalidate active status, expiry, target group and authenticated UID at commit.
  Missing profiles, another user's join, elevated roles, partial joins and
  duplicate/concurrent membership overwrites fail.
- Revocation blocks future joins, not existing members. Expired/revoked records
  are retained; automatic cleanup/TTL is not configured (TTL requires billing).
  Storage growth and read/write quotas need monitoring before launch.
- The exact-token design reduces guessing risk but is not server rate limiting
  or complete abuse protection. Spark quotas remain a shared availability limit.
- Device clock skew can reject client prechecks or an expiry near the maximum;
  rules are authoritative. A rejected commit must not be treated as membership.

The future Flutter UI must support copying/sharing a long token/link instead of
the old short-code field. Link domain/deep-link handling is not implemented.
Current FastAPI invite codes and Flutter join screens remain unchanged.

Validation: 49 local tests passed, including 15 invitation tests. On the final
run the Firebase CLI stalled after reporting successful execution and emulator
shutdown; the remaining process was terminated manually. All test assertions
completed, but clean CLI exit was not verified on that run.

## Additional local backend contracts

All modules below are JavaScript reference clients using Firestore rules, not
deployed endpoints or migrated Flutter repositories.

| Module | Implemented contract | Important boundary |
|---|---|---|
| [Assignments and progress](src/assignments.mjs) | Admin/lead manual assignments; assignee-owned status; group-visible reads | No reassignment/deletion or inferred Monday dates |
| [Assignment discovery](src/assignment-discovery.mjs) | Paginated own-group reading tasks and per-week status totals | Bounded client aggregation, not a global query or atomic snapshot |
| [Scheduling](src/scheduling.mjs) | Four chapter-wise preview modes, suggestions, atomic commits, admin week advancement | Explicit limits and unsupported modes; not a trusted server job |
| [Membership lifecycle](src/membership-lifecycle.mjs) | Coordinated leave/removal and explicit admin restoration | Immutable version history, fresh membership/discovery and no silent old-progress inheritance |
| [Canonical units](src/chapter-units.mjs) | 48 units from 53 chapters, including combined ranges | Rules independently validate canonical document keys/ranges |
| [Chat](src/chat.mjs) | Member-only messages; stable timestamp/ID pagination, max 50 | No edits; removal requires coordinated admin moderation |
| [Moderation](src/moderation.mjs) | Member reports, admin resolution and audited removal | No blocking, filtering or global moderation queue yet |
| [Member display](src/member-display.mjs) | Self-managed group-visible names separate from private profiles | No public email; removed atomically on coordinated departure |
| [Highlights](src/highlights.mjs) | Member-authored quotes/comments with original chapter 1–53 | Quote/paragraph accuracy is not verified against book content |
| [Reminder preferences](src/reminder-settings.mjs) | Owner-only toggles/time, India-first Asia/Kolkata | Stores preferences only; does not schedule notifications or send FCM |

Assignments use groups/{groupId}/readingWeeks/{week}/members/{uid}/assignments/{unitKey}.
Weeks must be canonical integers 1–10000 and unit keys canonical chapter/range
strings. This avoids ambiguous composite identifiers and enforces one assignment
per member/week/unit. Status is stored on the assignment, not in a duplicate
progress document. The scheduled date is an explicit timestamp or null. Reads
are scoped per member/week and capped at 48; no global assignment query yet.
Valid concurrent progress changes are last-write-wins.

Chat/highlights cannot be edited; deletion requires coordinated admin moderation.
Previously downloaded
data cannot be remotely revoked; server-read checks enforce current access on
new requests. Shared names are self-selected and can differ from private names.
Reminder defaults are both toggles off, 09:00; one personal time field does not
replace the old group notification schedule or separate daily-verse scheduling.

Earlier full emulator run: **138 tests passed, exit 0**. Emulators stopped normally.
Coverage includes 28 assignment/progress, 18 chat, 14 shared display and 29
highlight/reminder tests, in addition to the prior 49. Flutter/FastAPI source
remains unchanged; local test success is not mobile or production certification.

### Scheduling and week advancement

Scheduling milestone: **178 tests passed, exit 0**, including 40 dedicated scheduling
tests. The previously present scheduling module is now verified against emulator
permissions and concurrency; no claim of production readiness is implied.

- Chapter-wise previews support independent, rotating_window, dense_window and
  synchronized modes over canonical units. Explicit member order may be a subset.
- Remainders support manual/truncate (both report omitted slots) and cycle.
  Saptah, widths over 48, extend_last and round_robin are explicitly rejected.
- Hints must form a consistent nonnegative integral pattern; custom/ambiguous
  unsupported steps are rejected rather than silently interpreted.
- weeksAhead includes the current week. Dates are explicit instants or null;
  subsequent dates add seven UTC days, not inferred Monday/DST dates.
- Preview limits: 50 members, 12 weeks, 4096 slots. Atomic commit limits: 48
  assignments and 12 targets. Larger plans require explicit separate review;
  there is no cross-plan atomicity or automatic chunking.
- Commit rechecks group settings, roles, targets and existing assignments in a
  transaction. Any duplicate aborts the whole plan; races do not overwrite.
- Rules authorize canonical writes, not mathematical scheduling formulas.
  Authorized manual writes remain possible; client previews are not authority.
- advanceWeek uses an admin-only transaction adding exactly one. Rules forbid
  week jumps, overflow past 10000, or combining advancement with settings changes.
  Concurrent successful calls each increment once; this is not click deduplication
  or automatic generation of assignments for the next week.

No trusted scheduler, group summaries/global assignment discovery or deletion
cleanup has been implemented by this slice.

### Membership lifecycle and retention

Lifecycle milestone: **220 tests passed, exit 0**, including 42 lifecycle
tests. No deployment, billing or Flutter integration was performed.

- leaveGroup permits self-departure for noncreator/nonadmin members.
- removeMember permits admins to remove any noncreator and leads to remove
  ordinary members only. The creator cannot leave or be removed.
- One transaction creates groups/{groupId}/departures/{uid} and deletes canonical
  membership, private discovery and any shared display profile. Rules require
  all counterpart changes; partial removal attempts fail.
- Departure records contain only userId, removedBy, removedAt and reason. Actor
  identity and prewrite roles are enforced, and timestamps are server-generated.
- Departure before-images are immutable; subsequent departure/restoration cycles
  increment the canonical revision. Admins may inspect bounded audit lists;
  departed users may get their own marker, not other users' records.
- Historical assignments, progress, chat and highlights remain stored. Remaining
  members can still read them. Departed users lose new server access and cannot
  update progress; downloaded/cached data cannot be erased remotely.
- Departure blocks invitation rejoin and ordinary admin re-add for that UID.
  Explicit admin restoration atomically retains the prior marker and creates
  fresh ordinary membership/discovery. Old work remains history-only; only an
  explicit fresh assignment version can become active again. No client purge.
- Retention duration and account/group erasure remain excluded. Do not describe this as
  GDPR/privacy deletion or coordinated Auth account deletion.

### Reporting and moderation

Moderation milestone: **278 tests passed, exit 0**, including 58 new
moderation tests. Emulators shut down normally. Flutter/FastAPI remain unchanged.

- Current members can report each message/highlight once. Reporter UID is the
  document ID and must match authenticated identity. Reasons are spam, harassment,
  inappropriate or other; optional details are limited to 1000 characters.
- Reports preserve identity/reason/details and server creation time. Current
  members can get their own reports; admins can list up to 50. Other members
  and leads cannot read private reports. No global moderation queue yet.
- Admins resolve once to resolved/dismissed with authenticated resolver and server
  time. Resolving does not automatically remove the target.
- Admin removal atomically deletes content and writes a minimal immutable audit
  containing author/moderator UIDs, time and reason, not a copy of text/quote.
  Partial deletes and forged audits fail. Reports remain under deleted targets;
  removed IDs cannot be reused. Leads/authors cannot perform this removal.
- No report/audit purge, blocking, automated filters, appeal, moderation UI,
  retention deadline or account/group erasure. Previously downloaded content
  cannot be erased remotely. These are not full store/privacy compliance claims.
- Tombstone checks consume rule-document reads. Content creation batches should
  be limited to 18 items to reserve role/group lookup headroom. Normal sends
  create one item; this is not an unlimited concurrency quota.

### Assignment discovery

Latest full emulator suite: **299 tests passed, exit 0**, including 21 new
discovery tests. No rules, existing client modules or Flutter repositories changed.

- discoverMyAssignments reads the authenticated user's private group index,
  group metadata and only that user's scoped assignments. Supplied UID is not
  authorization: other users' indexes remain denied, including to group admins.
- Defaults: five groups per page and each group's current week. Maximum: ten
  groups and three consecutive weeks (including the starting week). An explicit
  weekNumber supports historical selection; weeks past 10000 are omitted.
- Each week returns assignments and total/notStarted/inProgress/completed counts
  for that user only. Empty groups/weeks remain represented. No roster, profile,
  collection-group query, denormalized aggregate or background write is needed.
- nextAfterGroupId follows the last index entry, not the last nonempty result.
  A full final page can require an additional empty page. Concurrent membership
  changes can alter pages; this is not snapshot pagination.
- All reads are server-only and sequential. Permission, missing-group and offline
  errors reject the entire call, without silent partial results or cached fallback.
  Reads are not an atomic snapshot and cannot retract previously downloaded data.
- At the maximum, reads return up to 1440 assignment documents, ten index entries
  and ten group documents. This is not a billing cap: Firestore bills documents,
  not one read per query; rule-dependent reads and empty-query minimums can add
  cost. Keep the defaults small and refresh deliberately rather than polling.

Global assignment queries, group-wide/all-time summaries, offline behavior and
Flutter dashboard integration remain separate work.

### Android connectivity

Flutter now has an isolated **debug-only Firebase authentication mode** connected
before the first operation. See [Flutter setup](../om_sai_ram/README.md#firebase-emulator-authentication-mode).
FastAPI remains the default full app. Basic group creation/discovery, invitation
joining/issuance/revocation and rosters now have an isolated Flutter gateway/UI,
but end-to-end validation is incomplete. Flutter also supports bounded manual
assignments, assignee progress and bundled reading with explicit completion
(2,090 Flutter tests pass), plus a bounded cross-group own-task dashboard,
group chat/member reporting, message/highlight admin moderation, highlights/reporting
confirmed group departure/member removal, admin settings/lead-role controls,
an opt-in group display-name directory and personal reminder preference storage.
The next group slice also connects admin-only atomic add-by-UID, exact optional
shared-name lookups for the visible roster page and a selected-week progress
overview of at most ten members. It reads at most 480 assignment documents per
page plus bounded metadata/roster/name reads; this is not a billing cap. Counts
are page-scoped, not whole-group/all-time totals. Private target profiles/indexes
are never read, and the existing Firestore rules are unchanged. See
[group-slice boundaries and validation](../om_sai_ram/README.md#firebase-group-onboarding-and-weekly-progress-slice---2026-10-15).
Actual Flutter SDK add/name/progress verification remains blocked by browser
access to the privately listening Firestore port; test doubles and successful
debug builds are not end-to-end certification. No existing emulator data was
cleared and no cloud resources were created.
Reminder preferences do not schedule local notifications or send push messages.
Bounded automatic scheduling previews/commits and admin week advancement are
also wired into Flutter, including explicit chapter-hint suggestions. Saptah
scheduling remains pending.
Optional explicit UTC date/time selection is now connected to new manual
assignments and the first week of automatic previews/hint suggestions. Unscheduled
remains the default. Manual creation confirms exact scope/date and distinguishes
acknowledged writes from failed reloads; date edits invalidate schedule previews.
Existing create-only rules and seven-UTC-day spacing are unchanged. See
[date-planning boundaries and validation](../om_sai_ram/README.md#firebase-assignment-date-planning---2026-10-15).
Real Flutter SDK dated-write verification is still blocked by integrated-browser
access to the private Firestore port; no existing emulator fixtures were cleared.
The JavaScript rule suite remains separate
from real Flutter SDK/device validation.
Private profile editing and logged-out password reset requests are also wired;
reset requests in emulator mode do not deliver real email. See
[account limits](../om_sai_ram/README.md#firebase-private-account-and-password-reset).
Signed-in password changes use current-password reauthentication through the same
named Auth instance, without Firestore or legacy API access. See
[password-change limits](../om_sai_ram/README.md#firebase-password-changes).

Standalone bundled reading now includes installation-local bookmarks, explicit
last-position saving/resume and exact original-chapter navigation. These reuse
local storage, not Firestore; they are shared across accounts and are not
cloud-synced. Resume is one saved relative position, not a full history log. See
[bookmark boundaries](../om_sai_ram/README.md#firebase-standalone-local-bookmarks--2026-10-15).

Assignment reading now reuses original-chapter bookmarks and adds a separate
explicit saved-position pointer per Firebase UID, with Continue/Clear in My
reading tasks. One acknowledged local JSON write preserves full assignment and
language identity; fresh server access still gates content and restoration.
These pointers are not Firestore-synced or encrypted, and logout does not erase
them. See [continuity boundaries and validation](../om_sai_ram/README.md#firebase-assignment-reader-continuity---2026-10-15).

The larger Flutter public reading/media/info slice now also exposes Aarti,
chapter audio, source-aware audio in both readers, the static daily programme
and a Firebase-specific FAQ. Audio hosting stays on GitHub Releases; no media
upload or Firestore contract change is involved. Public routes bypass profile
discovery while protected group routes remain guarded. See
[slice validation and remaining gates](../om_sai_ram/README.md#firebase-public-reading-media-and-information-slice--2026-10-15).

- Android emulator: development-machine services are normally reachable through
  10.0.2.2, provided they run on that emulator's host.
- USB device: use adb reverse for Auth 9099 and Firestore 8085, then localhost on
  the device. Emulator HTTP access must remain debug-only.
- VS Code Server: if Firebase runs on a remote Linux host, privately forward
  ports to the workstation running Android/adb first. Forward UI 4000 only for
  inspection. Never expose the UI or emulators through a public tunnel.

This config intentionally binds to loopback; do not change it to 0.0.0.0 just
to connect a phone. Use private forwarding instead. Auth emulator tokens are
unsigned and must never be accepted by a production server.

## Local trusted feed Functions

The [HTTP Functions](functions/index.mjs) now implement emulator-only public
live-darshan and festival fetching, replacing the corresponding trusted-fetch
responsibilities without PostgreSQL or Firestore writes. Flutter feed screens
are **not connected yet**; default/release behavior remains unchanged.

Use Node 22 and install both dependency sets. From the repository root:

```bash
npm --prefix firebase ci
npm --prefix firebase/functions ci --ignore-scripts
npm --prefix firebase run emulators:functions
```

If the host uses another Node version, a local, pinned runtime can be used
without changing system Node:

```bash
npm exec --yes --package=node@22.23.2 -- node firebase/scripts/functions-emulators.mjs
```

The launcher starts only Functions on 127.0.0.1:5001, with its own hub 4401 and
logging 4501; the existing Auth/Firestore session is not restarted. Occupied
ports cause failure, not termination of an existing service. Never run the
fixture-clearing `npm test` against the current fixture session.

| Public GET endpoint | JSON response |
|---|---|
| `http://127.0.0.1:5001/demo-om-sai-ram/us-central1/liveDarshan` | url, sourceUrl, fetchedAt, freshUntil, stale (always false) |
| `http://127.0.0.1:5001/demo-om-sai-ram/us-central1/festivals` | events, truncated, sourceUrl, fetchedAt, freshUntil, stale |

Each festival has a deterministic id, title, dateLabel, nullable eventDate
(`YYYY-MM-DD`, a calendar date, not a midnight/device-local timestamp) and
nullable description. Titles/descriptions are source text, not client HTML.
The actual four-column day/title/weekday/date layout is supported; weekdays
and day ordinals are not mistaken for dates/descriptions. Unknown dates stay
null. Empty/error parses fail instead of publishing fabricated empty calendars.

- Only fixed HTTPS temple sources are fetched. Redirects stay on the two temple
  hostnames and are capped at three. One ten-second deadline covers redirects
  and body reads; decoded HTML is capped at 1 MiB. Streams must be HTTPS m3u8
  URLs without credentials, fragments, IP literals or local/internal hostnames.
  Returned stream URLs are not fetched/proxied by the service, and a provider
  token's validity/playback is not guaranteed by cache freshness.
- Live results are fresh for 30 seconds; failed refresh never serves an expired
  cached stream. Festivals are fresh for six hours; on failure, the preceding
  successful result may be served explicitly stale until seven days old. Each
  feed coalesces simultaneous fetches and backs off failures for 60 seconds.
  These are process-local caches, lost on restart, not a durable archive or
  distributed refresh/abuse protection. At most 50 events are returned and
  truncation is disclosed.
- Only GET is supported, with local browser GET preflight. HTTP localhost and
  127.0.0.1 origins are allowed; remote/HTTPS/null origins are rejected. This is
  CORS, not user authentication or an OS network sandbox. Query parameters,
  request bodies and forced refresh are unsupported. Safe JSON errors use
  `error.code`/`error.message`: unavailable sources return 502, nonlocal runtime
  503, unsupported input 400, origin 403 and method 405. Responses use no-store.
- The runtime requires the demo project and Functions emulator. The launcher
  refuses credentials, Firebase tokens and WEB_HOST overrides, uses a temporary
  home/config, disables metadata discovery and redirects metadata token requests
  to a closed loopback endpoint. A real Google-auth subprocess test verifies
  credential acquisition is denied. No Admin SDK/data client is initialized.
- On GCP hardware the CLI may still warn that ADC is detected because its auth
  library recognizes hardware before consulting the detection flag; this warning
  is not suppressed. Multiple emulator suites for the same demo project also
  produce a warning: use the explicit ports, not automatic hub discovery. The
  Functions safeguards are not authorization to deploy or proof of an OS sandbox.

Repeatable checks (from the firebase directory):

```bash
npm run test:unit
npm run test:functions
npm run check:feeds
npm run check:feeds -- --require-live
```

`check:feeds` verifies real emulator HTTP guards and valid success/safe 502
responses without depending on website availability; `--require-live` additionally
requires both sources to succeed at that instant. It prints no signed stream
URLs/tokens or upstream HTML. It does not clear emulator data.

Validation on 2026-10-15: **96 Node 22 tests pass** (75 Functions source/cache/HTTP
checks and 21 configuration/credential-isolation checks). Coverage for service
logic/local guards is 95.71% lines and 95.04% branches, passing the 80% line gate.
Real emulator HTTP method/input/CORS checks pass; successful live and festival reads returned 200,
and all three current festival dates were verified. A later live refresh returned
the expected safe 502/cooldown error, while the source still parsed correctly in
a direct check; upstream availability is intermittent, not certified as constant.
Existing Auth/Firestore listeners still respond. No deployment, billing, database
write, fixture clearing, Firestore rule change or Flutter source edit was made.
Browser/private forwarding and HLS playback were subsequent integration gates;
see the client milestone below. Device QA, durable production caching, rate
limiting and production service approval remain gates.

### Flutter feed integration - 2026-10-15

The Firebase debug workspace now exposes public `/live` and `/events` routes,
with workspace/audio links and no Auth/profile or legacy API dependency in those
routes. FastAPI remains the default; this is not a release/backend cutover.

- The Flutter Functions gateway uses the validated emulator host, fixed port
  5001, demo project and us-central1 region. Reads omit credentials, reject
  redirects, enforce a 15-second deadline and a 256 KiB response bound, and
  validate complete response schemas, source URLs, freshness and literal dates.
- Festivals reuse the existing calendar UI, preserve unknown dates as labels,
  display fetched/fresh-until UTC times or explicit stale-cache status, and
  disclose truncated source data. A retry is an ordinary cached GET, not a
  forced source refresh. Failures never keep an old success presented as fresh.
- Web playback uses the existing HLS page with a pinned Functions endpoint;
  invalid endpoints/responses never fall back to FastAPI. Stream URLs are not
  placed in iframe query strings, logs or storage. Native Android fetches via
  the gateway and embeds validated data into the same bundled player asset;
  in-player retry bridges a new native feed read.
- Existing HLS controls, native-HLS fallback, codec-related video-only notice
  and external temple-browser action are retained. Refresh replaces the web
  iframe rather than retaining the first URL registered for all instances.

Validation: **2,117 Flutter tests pass**, including 27 new feed checks;
**116 selected Node 22 tests pass**, including 20 checks executing the actual
player script plus the existing 96 feed/configuration/isolation checks. New
Flutter sources/tests analyze cleanly; reused screens have pre-existing
deprecation/style infos, with no warnings/errors. Firebase debug web and Android
APK builds pass; no new dependency, rule change or fixture clearing was needed.

Browser QA at localhost:8790 reached real Functions responses and rendered all
three festival dates (October 19, 20 and 21, 2026). Desktop 1280x900 and mobile
360x800 screenshots were checked. Real live video played at 1280x720 with an
advancing playhead and nonblank sampled pixels; Chromium used the disclosed
video-only codec fallback. A browser-intercepted 502 displayed the safe error
with zero legacy requests, and retry restored real playback. Widget tests also
cover 320px/double-sized text, deadlines, disposal and refresh failures.

This is browser/emulator evidence, not Android device/WebView/audio certification,
guaranteed upstream availability, production security/rate/cost approval or
durable/distributed cache validation. Existing Auth/Firestore fixtures remain.

## Firebase-only backend exit checklist

### Group reminder schedule storage - 2026-10-15

The Firebase group detail screen now links to a protected reminder editor at
`/groups/{groupId}/reminder-schedule`. Any current member can read; current admins
and leads can explicitly confirm saves. Personal preferences remain separate.

- Canonical document: `groups/{groupId}/settings/notificationSchedule`. Exact
  fields are `initialDay`, `initialHour`, `initialMinute`, `deadlineDay`,
  `deadlineHour`, `deadlineMinute`, `escalationEnabled`, `timezone`, `groupId`,
  `revision`, `createdBy`, `createdAt`, `updatedBy`, `updatedAt`.
- Days use Monday=0 through Sunday=6; hours/minutes are bounded integers. The
  deadline must strictly follow the initial reminder in that same week. The
  timezone is fixed to `Asia/Kolkata`. These values are weekly intent, not firing
  instants, guessed assignment dates or device-local conversions.
- A missing document remains absent until an explicit save. The editor shows
  unsaved Monday 09:00 / Sunday 22:00 defaults with escalation intent on. Neither
  that toggle nor saving requests permission or schedules/sends notifications.
- Rules require an existing group and canonical membership, use prewrite
  admin/lead authority, bind updates to the authenticated UID and server time,
  preserve creation audit and require revision 1 / increments of exactly 1.
  Revision is bounded to 2,147,483,647. Listing, deleting and other settings paths
  are not authorized by this contract; departure revokes access without erasure.
- Flutter uses server-only reads and a transaction that rechecks actual SDK UID,
  current role, revision and precise `updatedAt`. Failed/uncertain saves retain
  the draft but require a server read before another write. Restoring a differing
  retained draft is explicit. Acknowledged writes with failed reload retry only
  the read. Late account/session/route changes cannot dispatch dialog writes.

Reference helper: [group-reminders.mjs](src/group-reminders.mjs). Run the isolated,
non-clearing rules suite against the existing local Auth/Firestore emulators:

```bash
cd firebase
npm exec --yes --package=node@22.23.2 -- node --test tests/group-reminders.test.mjs
```

The suite creates unique QA records and closes only its clients. Do not substitute
the ordinary `npm test` runner against a session whose fixtures must be retained.

Validation: **2,171 Flutter tests pass**, including **54 new checks** covering
models, controller recovery, widgets and SDK-shaped gateway doubles. New Dart
files analyze cleanly; Firebase debug web and Android APK builds pass. **49
selected Node 22 checks pass**: eight actual-emulator reminder/rule tests plus
21 local-configuration and 20 player-script regressions. Existing fixture-clearing
rule suites were not rerun against this session.

The rebuilt browser verifies logged-out deep-link redirection. Browser Auth is
reachable, but Firestore on 8085 still refuses connections; authenticated Flutter
SDK saves are therefore **not browser-certified**. SDK-double tests are not
transport/atomicity evidence; the JavaScript emulator tests independently check
rules. Native device permissions, scheduling and delivery remain unimplemented
for Firebase. No fixtures were cleared, cloud resources deployed, dependencies
added, legacy data imported/deleted or default backend switched.

The target is no FastAPI/PostgreSQL runtime dependency, not merely more Firebase
screens. Connected debug-workspace flows already block legacy HTTP access, but
the default/release app still uses FastAPI. This is not a completed cutover.
Bundled scripture, installation-local preferences and external audio hosting do
not need Firestore copies to remove the legacy backend.

Android reminder-delivery follow-up: the debug client now has a pure India-time
planner, explicit device opt-in/permission, confirmed per-device week anchors,
bounded native delivery and a crash-recovery journal. Saved cloud preferences do
not enable delivery. Web remains storage-only. Actual Android delivery, OS/reboot
restrictions and authenticated Flutter SDK/device QA remain unverified. See the
[device reminder milestone](../om_sai_ram/README.md#firebase-android-device-reminders---2026-10-15).
This increment passes 2,203 Flutter tests (32 new), clean new-file analysis and
debug web/APK builds. No new rules, Functions or fixtures were changed, and Node
rule/player suites were not rerun for these Flutter-only changes.

### Group archive and restore - 2026-10-15

Current members retain existing read permissions and private group discovery;
only a prewrite canonical admin can archive or restore. Legacy nine-field group
documents remain active. The first transition adds all four lifecycle fields:
`archived`, `lifecycleRevision`, `lifecycleChangedBy`, `lifecycleChangedAt`.
Each transition must toggle the flag, increment revision from zero/previous
revision (maximum 2,147,483,647), and use the actual UID and server timestamps.
Creation cannot include lifecycle metadata; later writes cannot remove it.

While archived, rules reject every group mutation except restoration, including
settings/week advancement, assignments/progress, chat/highlights, reports and
moderation, names, membership/departure, invites and group reminder settings.
Guards check both prewrite and postwrite group state: neither archive-plus-write
nor restore-plus-write batches can bypass read-only behavior. Private profiles
and personal preferences remain independently owner-writable. No erasure occurs.

Flutter reuses the admin transaction/controller for explicit confirmation,
exact Timestamp/version checks, retry-time role checks and uncertain-write
recovery. Group discovery and child views preserve readable history and show
read-only controls. Android removes archived-group reading slots on a local
admin operation or the next verified refresh/resume; other devices do not receive
a server push, and daily verses remain separate. Existing invite expiry still
applies after restoration; departed memberships are not recreated.

Validation: 2,218 Flutter tests pass (15 added in this increment), eight new
non-clearing archive-rule tests plus the eight reminder-rule tests pass, and
Firebase debug web/APK builds pass. The existing 48-write/12-target scheduling
ceiling also passes actual emulator rules while active/restored and fails while
archived. Scoped analysis has no errors/warnings and
six Riverpod `listenSelf` deprecation infos. Existing SDK doubles are not actual
authenticated Flutter browser/device QA. The prior Firestore-8085 browser
blocker and physical Android delivery remain unverified. Tests retain unique
QA fixtures; no fixture clearing, cloud deployment, dependency/default-backend
change, SQL import or permanent deletion was performed.

| Legacy backend area | Firebase replacement/status | Remaining gate |
|---|---|---|
| Email auth, token refresh, private profile, password changes | Firebase Auth SDK and owner-only Firestore profile | Real SDK/device QA; social/phone providers and verification remain unsupported |
| Groups, invitations, roles, membership and discovery | Firestore atomic contracts, versioned admin restoration and guarded Flutter flows | Ownership/account lifecycle, retention duration and real SDK/device QA |
| Group deletion | Reversible revisioned archive/restore; current members keep read-only history | Permanent erasure is excluded; ownership/account lifecycle remains pending |
| Manual assignments, progress, scheduling, suggestions and week advancement | Canonical-unit Firestore contracts, UTC dates, versioned archive/reassignment/replacement | Saptah and unsupported scheduling modes/limits remain pending; no permanent deletion |
| Own tasks and group progress | Bounded server-only reads and page-scoped client summaries | Whole-group/all-time totals require a separate aggregation design if required |
| Chat, highlights and moderation | Member-scoped Firestore records, reporting and audited admin removal | Global report queues, blocking/filtering, retention and completion-announcement parity |
| Global user search | Admin add-by-UID or recipient-controlled invitation | Do not recreate broad private name/email lookup without an approved discovery/privacy policy |
| Scripture/content versions | Bundled-only loading, original ranges and fallback; no content API calls | Remote version/update delivery is not reproduced; decide whether app-release content is sufficient |
| Live darshan stream proxy | Local HTTP Function and public Flutter player connected; real browser video verified | Android device/WebView/audio QA, upstream availability and production service controls |
| Festivals list and refresh | Local HTTP Function and public Flutter calendar connected with literal dates and freshness | Durable cache/production controls; forced refresh deliberately excluded pending admin policy |
| Group reminder schedules and delivery | Personal/group storage plus Android device opt-in, local planner, permissions and delivery wired | Real Android delivery/timezone/reboot QA and authenticated SDK QA; trusted FCM/server delivery excluded |
| Deletion and production cutover | Not implemented | Coordinated Auth/data deletion, migration/rollback, production config/rules/indexes, signing, SDK/device QA and owner approval |

The next reminder gate is real Android delivery/permission/timezone QA,
not storage or basic native wiring. Any trusted FCM delivery remains a
separate approved backend strategy; personal preferences alone are not delivery.
Do not deploy, enable billing or expose emulators publicly as part of local work.
Production Functions/scheduled delivery require separate cloud and cost approval.
Destructive lifecycle work additionally requires retention and ownership decisions.
Existing legacy data must remain untouched throughout.

## Existing tests

Continue the current backend pytest suite and Flutter test suite. The historical
Firebase rule suite had 299 passing tests; its fixture-clearing tests were not
rerun for this slice. Twenty-two non-clearing lifecycle/reminder-rule tests pass; Flutter
now passes 2,254 tests, including 35 earlier
configuration/auth/session/router/HTTP-isolation tests. These tests do not certify
production Firebase behaviour. Password reset email delivery,
Google sign-in, notifications and Android release builds need staging/device QA.

### Assignment and membership versions - 2026-10-15

- Canonical assignment documents accept all-or-none `archived`, `revision`,
  `changedBy`, `changedAt`. Legacy documents remain active revision zero.
  Every transition atomically saves the exact previous document under
  `assignments/{unit}/versions/{revision}`; history cannot be edited or deleted.
- Current prewrite admin/lead authority is required in an active group. Archive
  preserves progress/date; replacement creates fresh active work with reset
  progress, new creation audit and an explicit UTC date or null. Reassignment
  archives the source and creates a different current member's unit atomically;
  any existing target document rejects the whole transaction, never overwrites.
- Version/revision plus exact progress timestamps prevent stale confirmations.
  The Flutter workspace exposes archive/reassign/replacement and a server-only,
  one-document-at-a-time retained-version inspector; uncertain/acknowledged
  writes require manual verification before another lifecycle write.
- Admin-only restoration retains `departures/{uid}/versions/{revision}` and
  creates a fresh `member` role and private discovery entry with server joinedAt.
  Former roles/shared names are not inherited. Repeated departure/restore cycles
  retain immutable before-images; invitations/ordinary add cannot bypass them.
- Assignment creation must be at or after the current membership's exact
  joinedAt to accept progress. Archived/pre-rejoin rows remain readable but are
  excluded from active tasks, group totals and local reminder planning. Fresh
  active work requires an explicit replacement, not an automatic reset.
- Verified: **2,254 Flutter tests** (36 new), **22 non-clearing emulator tests**
  (six new assignment/membership checks plus eight group/eight reminder checks),
  debug web/APK builds. Scoped source/test analysis: no errors/warnings, four
  existing Riverpod deprecation infos. SDK doubles and emulator rules are not
  authenticated Flutter browser/device certification. The prior browser
  Firestore-8085 forwarding blocker and physical delivery QA remain pending.
- No fixture clearing, cloud deployment, production/default switch, dependency
  change, permanent deletion, SQL migration, commit or push was performed.

### Ownership transfer and account deactivation - 2026-11-22

- Ownership: the current owner hands a writable group to another current member
  in one batch (group `ownerUid`/revision, both roles, immutable
  `ownershipChanges/{revision}` audit). `createdBy` never changes; the former
  owner becomes a lead. Rules reject partial, stale, archived and nonowner writes.
- Account state: deactivation adds a server-time `deactivatedAt` marker to the
  private profile `users/{uid}`; restoration removes it. An active profile is
  therefore always exactly its three fields, so existing readers are unchanged
  and fail closed on a deactivated profile. Only the owner can toggle it, and
  the name and creation time cannot change in the same write. No list/delete.
- While deactivated, rules deny profile edits, group creation, invitation joins,
  admin adds, membership restoration and ownership handovers to that account.
  Existing memberships, history and the Auth account are retained, and existing
  group reads/writes are not revoked by rules; the Flutter session treats the
  account as not ready and turns off device reminders. This is a soft state,
  **not** Firebase Auth deletion or data erasure.
- The marker lives on the profile because membership rules already read that
  document: a separate state document pushed admin restoration over the rules
  lookup budget intermittently.
- Rules cannot enumerate groups, so "no owned groups" is checked by the client
  through its own private index (50 per page, at most 500 groups, fail closed)
  before the write and is not atomic with it. A raw client can skip it, but only
  for its own groups and can restore itself at any time.
- Reference helper: [account-lifecycle.mjs](src/account-lifecycle.mjs); six
  non-clearing tests in [account-lifecycle.test.mjs](tests/account-lifecycle.test.mjs).
- The archive guard reads the group before and after each write, so atomic
  message/highlight batches now fit 17 items (was 18). Fixtures were realigned.
- Permanent deletion: only the owner may delete `users/{uid}` and
  `users/{uid}/settings/reminders`. `deleteAccountData` first refuses while a
  group is owned, then leaves every writable group through the coordinated
  departure (markers and shared content stay under the UID, without a name),
  then deletes the private documents. Archived groups are read-only, so that
  membership remains and is reported. The Flutter client deletes the Auth user
  last and refuses up front when the sign-in is older than five minutes.
- Verified on fresh emulators: full suite **379/379**; Flutter **2,368** tests
  (SDK-shaped doubles). No live SDK/device certification or deployment.

### Provider sign-in and scheduling parity - 2026-11-22

- Google, Apple and phone sign-in plus explicit linking are connected in Flutter
  through `firebase_auth` and the existing `google_sign_in` package. New accounts
  continue to the explicit display-name step. A conflicting email or an
  already-used credential is refused; nothing is looked up by email or merged.
  [auth-providers.test.mjs](tests/auth-providers.test.mjs) checks this against
  the Auth emulator with test ID tokens and emulator SMS codes.
- Saptah is a group label only (legacy parity): both modes use the same weekly
  scheduling, settings and progress. There is no seven-day algorithm.
- `extend_last` and `round_robin` are available for the `independent` mode: when
  fewer units than one full week (members x width) remain after the plan, they
  are added to the final planned week. `extend_last` gives them to the last
  member; `round_robin` deals them one each in member order. Past the book end
  both behave like `truncate`. The legacy branches were unreachable, so this is
  a defined behaviour, not a port. Custom hint steps remain unsupported.

## Dependency audit boundary

The pinned tooling is development-only and is not packaged into Flutter. The
initial npm audit, after non-breaking fixes, still reports 16 transitive findings
(4 moderate, 12 high), including Firebase CLI and the JavaScript Firestore SDK.
Do not force-downgrade dependencies or hide findings to obtain a clean report.
Recheck the lockfile as upstream fixes become available. Keep these services
loopback-only and do not treat this tooling as a publicly hosted production API.