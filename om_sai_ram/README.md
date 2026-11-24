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

## Backend modes (updated 2026-11-22)

Firebase is now the default backend on Android and web; desktop and iOS default
to FastAPI. The dated sections below record earlier milestones and still say
"FastAPI default" or "debug-only": this section supersedes those statements.

| Build | Result |
|---|---|
| `flutter run` (debug, Android/web) | Firebase against the **local emulators** (`demo-om-sai-ram`) |
| `--dart-define-from-file=firebase.production.json` | Firebase against **your real project**; never touches an emulator |
| Release build without a project | Starts with a message explaining the missing configuration |
| `--dart-define=BACKEND_MODE=fastapi` | The original FastAPI app (`API_BASE_URL` as before) |

There is no fallback between emulator, real project and FastAPI. Project
settings, signing, provider setup and store steps are in the
[launch checklist](../docs/LAUNCH_CHECKLIST.md).

Also connected since the sections below were written: Google, Apple and phone
sign-in with explicit linking (`/account/sign-in-methods`), reversible account
deactivation, permanent account deletion, ownership transfer, Weekly Saptah as
a group label, and the `extend_last`/`round_robin` remainder modes. Verified on
2026-11-22 with **2,368 Flutter tests**, **379 emulator tests**, 75 Functions
tests, debug and release web builds, and debug and release APK builds. None of
it has run against a real Firebase project or a physical device yet.

## Screens for devotees (UI pass, 2026-11-22)

The Firebase mode screens were reworked for older Indian devotees (roughly 40 to
90 years old). This section supersedes older descriptions of the `/` workspace.

| Route | Screen |
|---|---|
| `/` | Home: language chooser on first open, a diya to light, the day's teaching, "Continue reading", and large tiles for Read, Listen, My groups, My reading tasks, Naam Jaap, Live Darshan, Programme, Festivals and Help |
| `/me` | Sign in / My account (email, Google, Apple, phone; name, reminders, sign-in methods, log out, deactivate, delete) |
| `/jaap` | Naam Jaap: a 108-bead counter kept on the device, reset each day |

- Theme "Temple at dawn": kumkum red buttons, saffron and marigold accents,
  sandalwood background, Mukta font (covers Devanagari). Colours are in
  [lib/core/theme/app_colors.dart](lib/core/theme/app_colors.dart); the theme is
  in [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart).
- Text size: the home "A" button cycles normal, large and extra large and is
  multiplied with the phone's own text size
  ([text_scale_provider.dart](lib/core/providers/text_scale_provider.dart)).
- Home wording is translated for English, Hindi, Marathi and Telugu in
  [home_text.dart](lib/features/firebase_home/data/home_text.dart); other
  languages fall back to English.
- Buttons are at least 56 px tall; body text is 17 to 18 sp before scaling.

Verified with **2,383 Flutter tests** (including contrast, 320/412/1024 px
widths at double text size, first-open language choice and Naam Jaap), debug web
and APK builds, and a real-browser click-through of the public screens and
email sign-up against the Auth emulator.

Known limits: no physical phone was used. Daily teachings and the
reading-screen buttons are English only. The Hindi, Marathi and Telugu wording
needs a native-speaker review. The Mukta font is downloaded on first use rather
than bundled.

## Study groups (group pass, 2026-11-23)

This section supersedes older group descriptions below. Group wording is in
[group_text.dart](lib/features/firebase_groups/presentation/group_text.dart)
(English, Hindi, Marathi, Telugu). Members are shown by the name they chose to
share, or "You" / "Member N"; account IDs are not shown to ordinary users.

| Route | Screen |
|---|---|
| `/groups` | My groups, with Start a group and Join a group |
| `/groups/new` | Start a group: name, chapters per week, starting chapter, chapter-wise or Saptah |
| `/groups/join?code=` | Join with an 8-letter code or a shared invite link |
| `/groups/:id` | Group home: my readings this week, invite, chat, shared quotes, members, reading times, all my reading, manage |
| `/groups/:id/manage` | For the group owner and group leads: plan readings, next week, who has not read, reading times, members, settings |

For the group owner (admin) and group leads:

1. **Start a group** from My groups. Your shared name is saved with the group.
2. **Invite** from the group home: tap Invite, then Share or Copy. The message
   holds an 8-letter code (shown as `ABCD-EFGH`) and a link. Stop the code at
   any time.
3. Members tap **Join a group** and type the code, or open the link.
4. **Plan readings** (Manage): tick who will read, put them in order, choose
   how many weeks, tap Show plan, then Save this plan. Nothing is saved before
   that.
5. Each member sees **My week** on the group home, opens the reading and taps
   Mark as read.
6. **Who has not read** shows the week's progress; Remind sends an editable
   message to the group chat.
7. **Next week** (Manage) moves the whole group on by one week after a
   confirmation. Readings already given stay as they are.

Leads can invite, plan, move to the next week, remind and remove ordinary
members. Only the owner can close or reopen the group, change roles, remove a
lead and moderate chat and quotes.

## Firebase emulator authentication mode

Run the emulators with the default debug build, or pass
`--dart-define=BACKEND_MODE=firebase` explicitly, for the
workspace with public reading/media/info and authenticated group/account flows.
This mode does not use the legacy auth provider,
JWT storage, API or navigation shell; all legacy HTTP requests are blocked
before storage/network access. Basic Firebase groups are now connected below.
Private profile editing and password changes are connected. Notification
delivery, SMS/social login and account erasure are not connected in this mode yet.

Start the [Auth/Firestore emulators](../firebase/README.md) before launching.
The project is pinned to demo-om-sai-ram; no cloud fallback or cloud credentials.
Auth runs on 9099 and Firestore on 8085. Keep both services private/loopback-only.

- Android emulator: `flutter run --dart-define=BACKEND_MODE=firebase --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`.
- USB Android: privately forward both ports with adb reverse; use the default
	127.0.0.1 host. If VS Code runs remotely, forward the ports to the adb host first.
- Web: `flutter run -d chrome --web-hostname=localhost --dart-define=BACKEND_MODE=firebase`.
	The page hostname must be localhost, not 127.0.0.1 or a remote hostname.
	The Auth endpoint may still use 127.0.0.1.

Release/profile Firebase builds, live projects, remote emulator hosts and native
desktop/iOS are rejected. Build configurations are compile-time, not a live
backend switch. Restart/rebuild without the define to return to FastAPI mode.

Signup creates Auth identity then a transactional self-profile containing only
displayName and server-created createdAt/updatedAt. Existing profiles/times are
preserved. An interrupted profile write does not delete Auth identity: the UI
keeps the authenticated account in a pending state with retry/read repair.
Firebase manages session persistence and tokens; no Firebase token is copied
to secure JWT storage. Logout does not claim to erase retained server data.

Web session restoration currently relies on the localhost/debug hook in
firebase_auth_web 6.3.0, seeded before SDK initialization with the emulator
endpoint only. Revalidate this path on dependency upgrades. The application
[pubspec.lock](pubspec.lock) is now eligible for version control to preserve
the tested resolutions; no files have been staged automatically.

Validation on 2026-10-13: **53 Flutter tests passed** (18 existing + 35 new);
analyzer had zero warnings/errors and 378 pre-existing infos. Firebase debug
web build and Android debug APK build passed. Browser/emulator checks covered
signup, reload restoration, login/logout, server profile timestamps and missing
profile repair without live Firebase or legacy API requests. Android compilation
is not real-device authentication certification. Kotlin-plugin compatibility
warnings remain for future Flutter toolchains.

### Firebase groups (validation in progress)

After a ready profile, choose **My groups**. The isolated workspace supports
chapter-wise group creation, paginated own memberships, invitation joining and
paginated member rosters. Creation writes group/creator-admin/private index
atomically; joining writes membership/private index atomically. All reads require
confirmed server data. Failures clear displayed results rather than serve cached
or partial pages. SDK membership roles and rules remain authoritative.

Admins can issue a 256-bit bearer token with 24-hour expiry and revoke the last
issued token. Tokens are not logged or persisted by the app. Refresh/navigation
clears the displayed token, not the server invitation; invite enumeration and
management of previously issued tokens are not provided. Clipboard copies are
outside app-state cleanup; share only with intended members. Duplicate joins
fail without resetting membership. Expiry/revocation races are checked by rules.

Rosters show UID/role, with explicit page-scoped opt-in shared-name lookup,
not private email/profile data. Session changes
dispose UID-bound state and discard delayed responses. No legacy shell or API
is used. Bounded automatic scheduling, opt-in shared names,
admin settings and lead-role controls are connected below. Global report queues
remain pending in this UI. Highlight sharing/reporting/moderation,
message-scoped admin moderation, group chat/reporting,
manual assignments, progress and
bundled assignment reading are now available as described below.

Validation update on 2026-10-14: the lazy-list scrolling test is repaired without
removing assertions, and all original **83 tests pass**. The redundant test import
was removed. Latest assignment integration brings the full suite to **148 passing
tests**. Analyzer has no errors/warnings, with 378 existing infos. Android debug
APK and Firebase debug web builds passed. End-to-end certification remains pending.
Real browser/emulator group checks were blocked by browser localhost connection
refusal despite HTTP 200 from the development terminal. Forward the web server
and emulator ports privately before retrying; real-device QA is also pending.

### Firebase manual assignments and progress

From a group detail, choose **Assignments**. The screen defaults to the signed-in
member and the group's current week. Select weeks 1–10000 and members from a
paged UID/role roster. Server reads are scoped to one member/week, capped at 48
canonical units. Other members' progress is group-visible, not editable by admins
on their behalf. Refresh is explicit; there is no background polling/global query.

- Admins and group leads may create one manual assignment at a time for a current
	member. The picker uses original chapters normalized into 48 units, including
	16–17, 18–19, 43–44 and 51–53. It never uses legacy SQL chapter IDs.
- Dates default to **Unscheduled** (null). New manual assignments can now use
	an explicitly selected UTC date/time, reviewed with the exact member/week/unit
	before creation. There is no inferred Monday or device-timezone conversion.
	Automatic generation has a separate workflow below; Saptah is unsupported.
- Duplicate-check transactions reject an existing unit without overwriting its
	metadata or progress. Only the assignee may set Not started/In progress/Completed;
	status updates use server timestamps and reload confirmed server data afterward.
- Permission/network failures clear results, not silently serve cached/partial
	data. UID/member/week changes discard stale responses. Sequential reads are not
	an atomic snapshot; concurrent valid progress updates remain last-write-wins.
- Choose **Read assignment** to open the bundled reader described below. Bounded
	scheduling is available separately; reassignment/deletion remain pending. Cross-group own tasks are
  now available through the dashboard below.
	Opening or scrolling text never automatically updates Firebase progress.

Validation: **148 Flutter tests pass**, including 65 new model/gateway/controller/
widget tests. SDK-shaped test doubles do not establish real Firestore transaction
or emulator behavior; the existing 299-test JavaScript rule suite is separate.
Android and web debug builds pass. Real Flutter SDK group/assignment flows,
concurrency and device QA still require reachable local emulators and execution.

### Firebase assignment reader and completion

From an assignment card, choose **Read assignment**. The route preserves the
group, assignee, week and canonical unit key; it rejects aliases/noncanonical
links rather than treating them as SQL chapter IDs. A fresh server assignment
read must succeed before local text is shown, so this is not offline assignment
access. Other members can read group assignments but cannot complete them.

- Bundled-only content loading never constructs the legacy API client or checks
	the FastAPI content endpoint. Default FastAPI reader behavior is unchanged.
- Combined Marathi units assemble all original chapters; translations already
	covering a range are not duplicated. Missing translations, including chapter
	50, use the existing Marathi fallback, labelled with its actual language.
- Reader language, adjustable font size and selectable text are available.
	Preferences remain installation-wide. Source-language chapter audio is now
	connected below; original-chapter bookmarks and explicit account-scoped local
	resume are also connected. Full history, in-text search and completion chat
	announcements remain pending in this assignment reader.
- **Mark assignment completed** is explicit, only for the signed-in assignee,
	and requires available content and current assignment access. Success appears
	only when a server reload observes Completed. Opening/scrolling never writes
	progress; failure clears assignment content/controls rather than claiming success.
- Returning refreshes the exact member/week assignment scope. Invalid links,
	missing assignments, denied access, session changes and unavailable content
	have explicit safe states. Previously downloaded data cannot be remotely erased.

Latest validation on 2026-10-14: **196 Flutter tests pass** (48 new reader tests),
including real bundled-content range/fallback checks and fake-gateway session,
route and completion tests. Analyzer: 378 existing infos, zero warnings/errors
(infos still yield analyzer exit 1). Firebase debug web and Android APK builds
pass. Real Flutter SDK/emulator and Android device end-to-end checks remain
pending; tests with gateway doubles do not certify server transaction behavior.

### Firebase My reading tasks dashboard

After signing in with a ready profile, choose **My reading tasks**. This guarded
workspace discovers only the signed-in user's group index and assignments,
without roster reads, private profiles of other users or collection-group queries.

- Five groups per page; next-page results replace rather than append. Refresh
	retries the current page, and Restart returns to the first page. Cursors follow
	group-index entries, including groups with no assignments. A full final page
	can require an additional empty request.
- Each group's current week is selected by default. Choose up to three weeks
	including the starting week, or enter an explicit week for history. Weeks above
	10000 are omitted. Empty groups/weeks remain visible.
- Counts show only your selected group/weeks on this page, not global, all-time
	or group-wide totals. **Read** opens the exact assignee/week/unit reader and
	refreshes the same dashboard page/options on return. Completion remains in
	the reader; the dashboard performs no writes or automatic polling.
- Reads are sequential and server-only, not an atomic snapshot. A malformed,
	missing, denied or offline response rejects the entire page; old results clear
	before requests. Session changes discard delayed responses.
- Gateway limits are ten groups and three weeks, with at most 1461 returned
	documents including the self profile. This is not a billing cap: document
	reads, security-rule dependencies and empty-query minimums can add charges.

Latest validation: **242 Flutter tests pass** (46 new task tests); analyzer has
378 existing infos, zero warnings/errors. Firebase Android APK and web debug
builds pass. Test doubles verify client behavior, not actual SDK/rules integration;
real emulator/device end-to-end checks remain pending.

### Firebase group chat and reporting

Choose **Chat** from group detail. Current members can read/send messages and
report individual messages. The roster is not queried for identity display:
messages show sender UID, not private names/email. No legacy API is involved.

- Server-only history defaults to 20 messages, maximum 50 per gateway request,
	newest first. Equal timestamps use descending document IDs. Cursors preserve
	original timestamp nanoseconds. Older pages replace history; Refresh newest
	returns to the head. Pages are not a frozen snapshot, and there is no polling.
- Text must be nonblank and at most 2000 characters. Sender UID comes from the
	SDK session; creation time is server-generated. Sending is not optimistic and
	auto-ID writes are never automatically retried. An acknowledged write clears
	the draft even if history reload fails. An uncertain write retains the draft
	and requires checking newest history before retrying to avoid duplicates.
- Reports use spam/harassment/inappropriate/other, with up to 1000 characters of
	details. A transaction checks the target and the reporter's existing report;
	duplicate reports cannot overwrite prior reports. Confirmation requires write
	acknowledgement. Dialogs are bound to their originating account.
- Errors clear history rather than return cached/partial data. Session changes
	discard delayed responses. Previously downloaded/copied content cannot be
	erased remotely. Reads and rule-dependent checks consume quota.
- Message-scoped admin report review, resolution and audited removal are now
	connected below. Blocking, filtering, retention purge, attachments and completion announcements are not connected
	in this UI. Reporting alone does not establish production/store compliance.

Latest validation: **336 Flutter tests pass** (94 new chat tests), analyzer 378
existing infos with zero warnings/errors. Firebase Android APK and web debug
builds pass. Tests use controlled SDK-shaped doubles; actual Flutter SDK/emulator
chat/reporting and device checks remain pending. FastAPI stays the default.

### Firebase message moderation

Actual group admins can open moderation for a message from chat. Server membership
roles are checked for entry and every operation; group leads/members cannot
moderate. Direct links still require ready Firebase session and server authority.

- Reports are scoped to one message, sorted by reporter UID, default 20/max 50
	per page. This is not a global/group-wide report queue. Private names/emails
	are not fetched. Errors and session changes clear/discard stale state.
- An open report may be resolved or dismissed once. Updates bind resolver UID
	to the SDK user and resolution time to the server. No reopening or report edits;
	resolving a report does not automatically delete the message.
- Removal requires confirmation and a reason. One transaction creates an
	immutable minimal audit and deletes the message; author UID comes from the
	target, moderator UID from Auth, time from the server. No text is copied into
	the audit. Duplicate removals cannot overwrite it, and rules reserve removed IDs.
- Reports remain readable to authorized admins beneath removed messages.
	The screen distinguishes missing targets from a confirmed audit record.
	Acknowledged writes remain acknowledged even if the subsequent refresh fails.
	Returning to chat refreshes its newest page.
- Previously downloaded content cannot be erased remotely. Global report queues,
	user blocking, filtering, retention cleanup and account
	erasure remain pending; this debug feature is not store/privacy certification.

Latest validation: **434 Flutter tests pass** (98 new moderation tests), analyzer
378 existing infos with zero warnings/errors. Firebase web and Android APK debug
builds pass. Controlled SDK-shaped doubles are not live SDK/rules validation;
actual emulator flows and device tests remain pending. FastAPI stays the default.

### Firebase group highlights

Choose **Highlights** from group detail. Members can share a quote/comment and
browse server-confirmed group highlights, with UID-only identity display.

- Inputs use original chapter numbers 1–53 (including 17/52), not SQL IDs or
	normalized assignment keys. Paragraph index is 0–2147483647, quote nonblank up
	to 500 characters, comment nonblank up to 2000. Quotes and anchors are manually
	supplied and **not verified** against scripture or a language/content version.
	Reader text-selection sharing is connected through the explicit review flow below.
- Pagination defaults to 20/max 50, newest timestamp then descending document ID.
	Cursors retain nanoseconds. Older pages replace the current page; errors clear
	results and retry the same cursor. Refresh newest returns to the head.
- Sender identity comes from Auth and creation time from the server. No optimistic
	creation or automatic retries. Acknowledged writes and reload failures are
	distinguished; uncertain writes retain drafts and require checking newest data.
- Each member may report a highlight once with reason/details. A transaction
	checks existing report and target, then creates the exact immutable report
	identity fields. Dialogs and delayed results remain bound to the original UID.
- Highlight review/resolution/removal is now connected below. Highlight editing,
  blocking and retention cleanup remain pending. No
	private profile copies, polling, global discovery or legacy API calls.

Latest validation: **593 Flutter tests pass** (159 new highlight tests), analyzer
378 unchanged infos, zero errors/warnings. Firebase debug Android APK and web
builds pass. SDK-shaped doubles do not verify actual emulator/rules behavior;
real SDK and device end-to-end checks remain pending. FastAPI stays the default.

### Firebase highlight moderation

Actual admins can open **Moderation** on a highlight. The shared moderation
workflow now distinguishes messages from highlights with explicit target kinds;
identical IDs in the two collections have separate reports, audits and state.
Existing message moderation routes and behavior are preserved.

- Highlight previews show original chapter, paragraph, quote and comment, labelled
	as user-supplied/unverified. Members and group leads cannot moderate; direct
	links and every operation require current server admin membership.
- Reports use bounded reporter-UID pagination and one-way resolve/dismiss actions.
	Removal requires confirmation/reason and atomically writes a minimal immutable
	highlight audit plus deletes the target. Audit author UID is taken from the
	highlight; moderator UID/time are Auth/server-bound. No quote/text is copied.
- Reports remain after removal and IDs stay reserved by rules. Refresh failures
	are distinguished from acknowledged writes. Returning refreshes newest highlights.
	Session changes and permission failures clear/discard stale results.
- No global report queue, blocking, automated filtering, retention purge or account
	erasure. Previously downloaded content cannot be remotely erased. Reader-selection
	sharing is connected below; live SDK/device certification remains pending.

Latest validation: **702 Flutter tests pass** (109 new highlight-moderation tests);
the original 98 message-moderation tests remain passing. Analyzer: 378 existing
infos, zero warnings/errors. Firebase web and Android APK debug builds pass.
SDK-shaped doubles verify client contracts, not actual transport, server rules,
transaction retries/atomicity or acknowledgements. FastAPI remains the default.

### Firebase group departure and member removal

Group detail now offers confirmed self-departure for nonadmin members/leads.
Admins may remove other noncreator members; leads may remove ordinary members
only. The creator cannot leave or be removed. Actual server roles are rechecked
inside the transaction, not inferred from UI state or claims.

- One transaction creates a departure marker/version and deletes membership,
	the target's private discovery index and optional shared member display profile.
	The gateway never reads another user's private index. All reads precede writes.
- **Assignments, progress, messages and highlights remain retained.** This is
	access revocation, not account deletion or privacy erasure. Departed users need
	explicit admin restoration with fresh membership/discovery. Previous work stays
	history-only until explicitly replaced; invitations/ordinary add cannot bypass this.
- Confirmations disclose retention and the rejoin restriction. Actions are bound
	to the original account/group/target; account changes discard delayed results.
	Write acknowledgements remain distinct from subsequent reload failures, and
	actions are not automatically retried by the UI.
- Self-departure returns to own groups with refreshed discovery; removal refreshes
	the roster and invalidates local session-dependent data. Other clients lose
	access on their next server request, not through guaranteed push. Previously
	downloaded/copied content cannot be erased remotely.
- Ownership transfer, account/group erasure, rejoin restoration and retention
	cleanup are not implemented.

Latest validation: **815 Flutter tests pass** (113 new lifecycle tests). Analyzer
has 378 existing infos, zero warnings/errors. Firebase Android APK and web debug
builds pass. SDK-shaped tests verify client contracts, not live server/rules
behavior or device certification. FastAPI remains the default.

### Firebase group settings and lead roles

Actual admins can open **Group settings** to edit name/description, chapter-wise
width (1–48) and start chapter (1–53). Saptah groups support name/description
editing only in this UI; this does not implement Saptah scheduling. Settings
changes **do not reschedule existing assignments**.

- A transaction rechecks current admin membership and compares the original
	server updatedAt timestamp at full nanosecond precision. Stale edits are
	rejected rather than silently overwriting another admin's changes.
- Writes change only allowed settings and server updatedAt. Creator, creation
	time, mode and current week are untouched; week advancement is separate work.
- On the roster, admins can promote members to group lead or demote leads to
	member. Expected roles are checked on transaction retries. Creator/self/admin
	targets are protected; granting admin or transferring ownership is unsupported.
- Forms and confirmations are UID-bound; duplicate submits are blocked. Success
	invalidates affected local permissions and refreshes the roster. Write ACK and
	reload failure are distinct. Other clients use new authority on their next
	server request, not guaranteed push.

Latest validation: **991 Flutter tests pass** (176 new administration tests).
Analyzer: 378 existing infos, zero warnings/errors. Firebase web and Android APK
debug builds pass. SDK-shaped tests are not live SDK/rules/device certification.
No ownership transfer, extra admins, automatic scheduling or rejoin restoration.

### Firebase opt-in group display names

Choose **Group display names** from group detail. Members may explicitly publish
or change a group-visible name, independent of their private profile. The initial
form never copies private names/email. Display names are nonunique, unverified
text; UID remains visible and is always the authorization identity.

- Stored fields are exactly displayName, createdAt and updatedAt. Names must be
	nonblank and at most 100 characters. A transaction rechecks current membership,
	preserves original creation timestamp precision and sets update time on server.
- The directory lists only published displays, not the full roster, default 20/
	max 50 per document-ID page. Pages replace prior results; your own published
	name is read separately, including when it lies outside the visible page.
- Publishing requires disclosure/confirmation. **Unpublishing is not supported**
	under current rules; the UI offers publish/change only. Coordinated departure
	removes the shared display, not previously downloaded/copied names or history.
- UID-bound forms/dialogs discard delayed account responses; errors clear shown
	directory data. Acknowledged writes remain acknowledged if reload fails.
	No polling, private identity copies or automatic roster backfill.
- Roster/chat/highlight rendering remains UID-only in this slice; no per-row
	lookup fan-out or historical name snapshots. Name changes are not identity proof.

Latest validation: **1,143 Flutter tests pass** (152 new), analyzer 378 existing
infos, zero errors/warnings. Firebase Android APK and web debug builds pass.
SDK-shaped doubles are not live Firebase/emulator or device certification.
FastAPI stays the default; real runtime validation remains pending.

### Firebase personal reminder preferences

Choose **Personal reminder preferences** in the Firebase workspace, or open `/reminders`
with a ready Firebase session. **Preferences only — notifications are not
scheduled or sent.** This does not invoke the existing FastAPI-mode notification
service, request OS permission, register device tokens or send FCM.

- Owner-only SDK UID storage at `users/{uid}/settings/reminders`. Server-only
	reads never create missing preferences or fall back to cached settings.
- Missing preferences show unsaved defaults: both toggles off, 09:00, timezone
	`Asia/Kolkata`. Reading and daily-verse preferences share this one India time;
	it is not a device-local or general timezone schedule.
- Explicit Save replaces exactly five preference fields plus server `updatedAt`.
	Strict validation rejects malformed/unknown fields and retains Timestamp
	precision. Saving both toggles off does not delete the document.
- Account-bound forms and delayed results prevent cross-account display. Failed
	reads clear confirmed settings; uncertain saves retain a disabled draft until
	an explicit server read. Acknowledged saves remain distinguished from reload
	failures. No polling or automatic write retries.

Latest validation: **1,303 Flutter tests pass** (160 new reminder tests); analyzer
378 existing infos, zero errors/warnings. Firebase debug web and Android APK
builds pass. SDK-shaped doubles are not live SDK/rules or device certification.
FastAPI remains the default; delivery and real runtime validation remain pending.

### Firebase automatic scheduling and week advancement

Admins and group leads can open **Automatic scheduling** from group detail
(`/groups/:id/scheduling`). Select an explicitly ordered subset of members from
the paged UID roster; selection persists across replacement pages. This is not
a claim that every group member is covered.

- Four chapter-wise modes: independent, rotating window, dense window and
	synchronized. Remainders support manual review, truncate and cycle. Manual and
	truncate omit overflow and show every unfilled slot; cycle wraps canonical units.
- Previews use the 48 canonical units, at most 50 selected members, 12 weeks
	**including the current week**, and 4,096 requested slots. Week numbers cannot
	exceed 10,000. Settings are reread for previews; edits invalidate confirmation.
- Confirmed commits create **1–48 assignments for at most 12 target members** in
	one transaction. Larger previews are viewable but not committable. No hidden
	chunking, skip-existing or overwrite: any duplicate aborts the whole plan.
	Transactions recheck exact scheduling settings, actual actor role and every
	target's current membership on retries, with all reads before writes.
- UI dates default to **Unscheduled**. An optional first-week UTC date/time
	now flows through manual previews and hint suggestions, with seven-UTC-day
	increments, not inferred Monday/device-local dates.
	Saptah scheduling and other remainder modes are unsupported. Chapter-hint
	suggestions are available as described below.
- **Advance week +1** is a separate admin-only confirmation, allowed independently
	of scheduling mode. It increments the transaction-current week, not a stale
	displayed week; concurrent successful calls each increment once. No assignments
	are generated and no settings are changed by that action.
- UID/generation-bound confirmations discard stale account results. Acknowledged
	writes and reload failures are distinct. Unverified outcomes prohibit blind
	retries: explicitly reload server head, inspect assignments/current week, then
	make a new preview/confirmation. No polling, jobs or reminder delivery.
- Firestore rules authorize assignment writes; they do not certify the preview
	formula, whole-roster coverage or date semantics as a trusted server schedule.

Latest validation: **1,579 Flutter tests pass** (276 new scheduling tests);
analyzer 378 existing infos, zero errors/warnings. Firebase debug web and Android
APK builds pass. SDK-shaped doubles do not certify live SDK/rules/device behavior.
FastAPI remains the default; real runtime validation remains pending.

### Firebase pattern suggestions

In **Automatic scheduling**, select at least two members and enter original
chapter hints for at least two selected UIDs, then choose **Suggest from hints**.
Hints follow their UIDs when selections are reordered; removing a selection
removes only that UID's hint. Displayed positions are one-based; inference uses
the actual gaps between positions, not just the first two chapter differences.

- Original chapters normalize into canonical units. Every supplied hint must
	agree with a nonnegative integral unit step and a valid inferred start.
	Duplicate positions, inconsistent hints, fractional/negative steps and custom
	unsupported steps are rejected rather than guessed.
- Zero step suggests synchronized; a step equal to group width suggests rotating
	window; otherwise step one suggests dense window. With width one, rotating
	window takes precedence. One week's hints cannot distinguish independent from
	rotating window; inference does not claim otherwise.
- Suggestions reload server settings/roles and show inferred mode, canonical
	start and unit step separately from manual input. Edits invalidate the preview
	and confirmation. Account switches and disposal discard delayed results.
- Suggestions are read-only until the existing explicit atomic confirmation.
	Existing preview/commit limits still apply; oversized suggestions can be viewed
	but cannot commit. No automatic writes, jobs, dates or notification delivery.

Latest validation: **1,663 Flutter tests pass** (84 new suggestion tests);
analyzer 378 existing infos, zero errors/warnings. Firebase debug web and Android
APK builds pass. SDK-shaped doubles are not live SDK/rules/device certification.
FastAPI remains the default; real runtime validation remains pending.

### Firebase private account and password reset

Ready Firebase sessions can choose **Edit private profile** (`/account`) to edit their
private display name. This does not change group-visible names, Auth display
names, email, phone or permissions. Other members cannot read this profile.

- Server-only reads require the exact private profile schema. Missing or malformed
	profiles fail closed; account editing never creates a replacement profile.
- Name-only transactions preserve original `createdAt` Timestamp precision and
	use a server `updatedAt`. The workspace name refreshes only from a confirmed
	server read, without redirecting away from the acknowledged-save state.
- Account switches, disposal and delayed responses are guarded. Failed reads
	clear confirmed profile data. Uncertain saves retain a disabled draft pending
	explicit server verification; acknowledged reload failures do not repeat writes.

Logged-out users can choose **Forgot password?** on login (`/forgot-password`).
The SDK requests a reset for the validated email without changing auth state or
accessing Firestore. Success is account-neutral and does not establish account
existence or delivery. Network/rate-limit errors use safe messages, not raw SDK
responses. **The Auth emulator sends no real email**; local emulator tooling is
where developers inspect reset action links. The app never retrieves or logs codes.

Email changes, signed-in reset, verification, social login and account
erasure remain unsupported in this slice. Real reset delivery requires staging QA.
Password changes are available through the separate flow below.

Latest validation: **1,821 Flutter tests pass** (158 new account tests);
analyzer 378 existing infos, zero errors/warnings. Firebase debug web and Android
APK builds pass. SDK-shaped doubles are not live SDK/rules/device certification.
FastAPI remains the default; real runtime validation remains pending.

### Firebase password changes

From the private-profile screen, choose **Change password**
(`/account/change-password`). This ready-session-only flow requires a linked
email/password provider and the current password. It uses the SDK account email,
not a caller-supplied identity, to reauthenticate before updating the password.

- Current password must be nonempty; new passwords must match confirmation and
	contain at least six characters. Passwords are not trimmed; Firebase enforces
	its actual server password policy.
- Reauthentication errors never dispatch a password update. Account checks run
	across asynchronous boundaries, including failed futures and auth transitions.
- Any error after update dispatch is treated as uncertain. No automatic retry:
	the form remains blocked across route reopening until session change. Log out,
	verify by logging in, and use Forgot password if needed. Already-dispatched
	updates cannot be rolled back when an account changes.
- Password fields clear on valid submission, completion, session change and
	disposal. Secrets are never held in provider state, written to Firestore or
	persistent storage, logged, or sent to the legacy API. Clearing Dart strings
	does not guarantee secure memory zeroing.
- Successful acknowledgment does not claim other sessions were revoked; no
	custom token-revocation or forced sign-out mechanism is implemented.

Latest validation: **1,895 Flutter tests pass** (74 new password tests);
analyzer 378 existing infos, zero errors/warnings. Firebase debug web and Android
APK builds pass. SDK-shaped doubles do not certify live SDK/emulator behavior.
FastAPI remains the default; real runtime/device verification remains pending.

### Firebase reader highlight sharing

Select text in the Firebase assignment reader, then choose **Share selected text**.
The review composer preserves the exact quote (at most 500 UTF-16 code units),
shows its actual source language including fallback, and requires an explicit
original chapter, paragraph index and comment. Blank, oversized, invalid-offset
or split-surrogate selections are rejected, not silently truncated.

- Chapter choices are bounded by the selected source and assigned canonical unit.
	Combined-unit source segments retain provenance, but paragraph anchors are
	**user-supplied and unverified**, never inferred from assembled text offsets.
- Assignment access is freshly checked before review and before sending. Session,
	selection, content reload, language and route changes invalidate stale reviews.
	A member may share while reading another member's assignment through their own
	current group membership. Sharing never changes reading progress.
- Opening, selecting or cancelling never writes. Explicit sharing uses the
	existing six-field highlight contract and membership checks, not legacy APIs.
- Acknowledged sends cannot be resubmitted by the composer if refresh fails.
	Uncertain sends stay blocked across reader reopening until explicit server-head
	verification. Absence from a bounded page is not proof of non-delivery; review
	before deciding whether to send again. Guards are application-memory-only;
	drafts are not persisted and app restart does not preserve delivery guards.

Latest validation: **1,929 Flutter tests pass** (34 new reader-sharing tests);
analyzer 378 existing infos, zero errors/warnings. Firebase debug web and Android
APK builds pass. SDK-shaped doubles do not certify live SDK/rules/device behavior.
FastAPI remains the default; real runtime/device verification remains pending.

### Firebase standalone bundled reading

Choose **Read Satcharita** from the Firebase workspace, including while logged
out. `/reader` lists actual bundled entries; `/reader/:chapterNumber` accepts
strict original chapter numbers 1–53, not SQL IDs or group assignment units.

- Search titles or chapter numbers, including numbers inside merged ranges.
	Original-number jump and previous/next navigation reach chapters omitted from
	a translation's catalogue, with an explicitly disclosed Marathi fallback.
- Marathi originals remain separate; translated merged entries preserve their
	actual ranges. No fabricated 53-entry catalogue or assignment assembly.
- Language and clamped font settings are installation-wide. Text is selectable,
	RTL where needed, with mobile-wrapping controls and explicit local retry.
- Reading performs no legacy API/content-update checks, Auth profile reads,
	Firestore access, group progress writes or notification operations. Existing
	protected group routes remain guarded; this public book is not assignment access.
- Bundled text works offline **after startup**. Firebase mode still requires the
	existing named emulator bootstrap; fully offline boot is not claimed.
	Standalone bookmarks and explicit last-position resume are connected below;
	full history and standalone highlight sharing are not yet connected. Chapter
	audio is connected below.

Latest validation: **1,968 Flutter tests pass** (39 new bundled-reading tests);
analyzer 378 existing infos, zero errors/warnings. Firebase debug web and Android
APK builds pass. Live SDK/emulator/device validation remains pending.
FastAPI remains the default.

### Firebase standalone local bookmarks — 2026-10-15

The standalone reader now supports bookmarking the requested original chapter
and opening saved chapters from the catalogue. Merged translations preserve the
requested number: bookmarking original 17 saves 17, not the entry start 16.

- Reuses existing installation-local bookmark storage, shared with the default
	reader and across accounts. No Firestore storage or cloud/account sync.
- Bookmark writes wait for initial storage loading, preserve existing saved
	chapters and only update confirmed state after a successful save. Save errors
	leave the toggle retryable and show an error rather than claim success.
- Saved original numbers are sorted; out-of-range numeric entries are hidden.
	Bookmarking does not write assignments, completion, streaks or resume history,
	and does not initialize Auth, legacy APIs or notification delivery.
- Assignment-reader bookmarks and explicit resume are connected in the continuity
	slice below. Standalone last-position resume is connected below; a full history
	log remains pending.

Validation: **1,973 Flutter tests pass**, including **44 bundled-reader tests**.
Targeted analysis of the provider, reader and tests has no issues. Live browser,
Firebase SDK/emulator and Android device verification were not performed for this
slice. FastAPI remains the default; no deployment or billing changes.

### Firebase standalone saved reading position — 2026-10-15

The standalone reader now offers **Save reading position** in the chapter toolbar.
The catalogue's **Continue reading** entry opens the exact saved original number;
its relative scroll position is restored after bundled content loads.

- Reuses the existing installation-local resume keys, shared with the default
	reader and across accounts. This is one last explicitly saved position, not a
	chapter history log, account-specific storage or cloud synchronization.
- Opening or scrolling does not save, record a streak or complete an assignment.
	Save success is shown only after storage acknowledges both writes; failures
	show an error and leave the control retryable. The two preference writes are
	not atomic, so a partial failure can leave mismatched persisted values.
- The saved original number is preserved for merged translations. Invalid saved
	numbers are hidden; nonfinite stored offsets restore to the top, and finite
	offsets are clamped to the current scroll range.
- Restoration checks the current chapter/language after asynchronous loading.
	Relative offsets are approximate across language, font and viewport changes;
	this is not a paragraph anchor. No automatic save on exit or browser shutdown.
- Assignment-reader resume is connected in the continuity slice below. A full
	history log remains pending. Audio is connected below.

Validation: **1,982 Flutter tests pass**, including **53 bundled-reader tests**.
Touched provider, screen and tests have no editor diagnostics. Live browser,
Firebase SDK/emulator and physical Android checks were not performed for this
slice. FastAPI remains the default; no deployment or billing changes.

### Firebase public reading, media and information slice — 2026-10-15

The workspace now links public bundled reading, **Audio**, **Daily Programme**
and **Frequently Asked Questions**, alongside existing authenticated group,
reading-task and account flows. Public routes bypass session/profile discovery;
private routes still require a ready Firebase session. Legacy auth/API providers
and the legacy navigation shell remain isolated.

- `/audio`, `/audio/aarti` and `/audio/satcharitra` reuse the existing catalogue,
	GitHub Releases audio hosting and player, with direct-link back navigation.
	Aarti now exposes the shared seek/play/pause/stop player as well.
- Standalone and assignment readers select audio by actual loaded source
	language and original chapter numbers, not SQL IDs or requested-language
	guesses. Combined Marathi assignments expose each original; merged audio
	tracks are deduplicated. Unsupported languages do not silently substitute audio.
- Reader controls expose loading/error states, retry, seek and stop. Audio is
	public and installation-wide, can continue across route/account changes and
	never changes assignment status, completion, streaks or resume preferences.
- The daily programme remains bundled/static, not a live temple schedule feed.
	Firebase FAQ copy describes long expiring invitations, explicit completion,
	local preferences and current Saptah/reminder/departure limitations accurately.
- No scripture/media upload, Firestore rule changes, deployment or billing.
	Festivals and live-stream processing remain outside this slice.

Validation: **1,988 Flutter tests pass**, including **58 bundled/public-media
tests** and **49 assignment-reader tests**. Firebase debug web and Android APK
builds pass. Scoped analysis reports 43 informational lints, no errors/warnings.
Browser checks rendered the workspace, Aarti, chapter audio, programme and FAQ
at desktop width, plus chapter audio and the fallback-language reader at mobile
width, without detected horizontal overflow. A hosted hub photo still used its
fallback in the browser environment; the existing external source is not a
guaranteed asset/CDN. Actual hosted playback, interruptions/native caching,
authenticated SDK/rules workflows and physical-device QA remain release gates.

Local preview: `http://localhost:8790` (loopback only). On remote development
hosts, privately forward web 8790, Auth 9099 and Firestore 8085. Open the web app
with hostname `localhost`, not `127.0.0.1`, because of the existing debug Auth
restoration hook. FastAPI remains the default full/release app.

Next larger slices:
- Group-management parity: assignment management and policy-approved lifecycle
 work; deletion/rejoin need design
	approval before implementation.
- Scheduling and delivery: unsupported scheduling modes, local reminders
	and an explicitly chosen trusted delivery/lookup strategy for push/festivals/live.
- Production readiness: full SDK/device QA, owner-approved Android identity and
	staging/cloud setup, retention/moderation policies and cutover acceptance.

### Firebase group onboarding and weekly progress slice - 2026-10-15

Group detail now exposes **Add member by UID** to actual admins. Confirmation
adds an existing Firebase profile as an ordinary member, writing canonical
membership and the target's private discovery index in one transaction. Leads
and ordinary members cannot add; duplicates, self-adds and departure markers
are rejected. The app never reads a target private profile/index or searches
users by email/name. Existing rules validate profile existence and atomicity.
Invitations remain the recipient-controlled alternative; production consent
and abuse policy still need approval.

- Admin writes reuse the existing acknowledgement/verification controller.
	Acknowledged writes are not repeated after reload failure. Uncertain outcomes
	require a server roster refresh; the unconfirmed target UID is retained for
	verification, scoped to the account/group and cleared after acknowledgement.
- **Load shared names for this page** fetches only the displayed roster UIDs,
	at most 20 exact group-visible documents plus group/self-member checks.
	Names are optional, unverified, nonunique and never authorization identities.
	UID/role remains visible; failed lookups discard names, and roster/account
	changes cannot display names from a previous page.
- **Weekly group progress** opens `/groups/:id/progress?week=N`. The group link
	selects its current week; a direct link without a week defaults to week 1.
	Weeks 1-10000 are supported. Up to ten roster members per page have exact
	selected-week assignment counts and links preserving both member and week.
- Totals are for the **displayed members page**, not the whole group or all time.
	Assignment reads are capped at 48 canonical units per member: at most 480
	assignment documents per page, plus bounded roster, name and repeated
	self-profile/group/membership reads. These bounds are not billing caps:
	security-rule reads and minimum query charges also apply.
- Reads require confirmed server data. A denied, malformed or failed member/name
	read rejects the entire overview page. Refresh replaces results, retries the
	current cursor and never polls; First members page restarts pagination.
	Sequential reads are not an atomic snapshot. Session changes discard delayed
	responses, and acknowledged admin/departure mutations invalidate overview state.
- No assignment deletion/reassignment, account/group deletion, rejoin/restore,
	global lookup, aggregation writes, cloud configuration or production cutover.

Validation: **2,027 Flutter tests pass**. Scoped analysis reports no issues;
Firebase debug web and Android APK builds pass, with existing WebAssembly and
Kotlin-plugin compatibility warnings. Focused tests cover SDK-shaped atomic
writes, permissions/retries, uncertain outcomes, privacy, immutable name bounds,
pagination, page totals, account changes, exact links and narrow/large-text UI.
These doubles do not certify actual Firestore SDK/rule behaviour.

Desktop/mobile browser checks confirm unready/logged-out progress links return
to the account workspace. A disposable local Auth signup succeeded, but the
integrated browser could not reach Firestore at 127.0.0.1:8085 while the emulator
was listening privately on the development host. The QA Auth account remains
pending profile setup; existing emulator data was not cleared. Authenticated
add/name/progress SDK flows therefore remain unverified until private port
forwarding is available. Physical-device and production QA also remain pending.
The existing preview is `http://localhost:8790`; FastAPI is still the default.

### Firebase assignment date planning - 2026-10-15

New manual assignments and automatic schedule plans now offer optional native
date/time pickers labelled **UTC**. Both selections must be accepted before a
value is published; cancellation leaves the draft unchanged, and Clear explicitly
returns to Unscheduled. Opening a picker does not save a date. The picker selects
minute precision, while gateway/controller inputs preserve JavaScript-compatible
millisecond precision. Only UTC instants within Firestore years 1-9999 are accepted.

- Manual creation reviews the exact group, member UID, week, canonical unit and
	date before writing. Account/member/week changes invalidate confirmation;
	duplicate assignments are not overwritten or rescheduled. Only actual admins
	and leads can create; only assignees can change their own progress.
- Acknowledged manual writes remain distinct from failed verification reloads.
	Failed/unconfirmed creates do not claim success; another creation is blocked
	until confirmed assignment data is reloaded. Date drafts remain available after
	verification, while an acknowledged creation clears the date back to null.
- Automatic previews and chapter-hint suggestions carry the chosen first-week
	instant unchanged. Each later week adds exactly seven UTC days, even across
	device DST changes. End-of-range overflow rejects the plan without writes.
	Date changes invalidate preview and any open confirmation; commit uses only the
	immutable reviewed plan and existing all-or-nothing/create-only protections.
- No date edits to existing assignments, scheduling formula changes, custom
	intervals, device-timezone conversion, reminders/push, new Firestore rules,
	cloud changes or production cutover. FastAPI remains the default.

Validation: **2,052 Flutter tests pass**, including 25 added date-workflow checks.
The final picker checks pass after an explicit async mounted-guard cleanup;
scoped analysis reports no issues. Firebase debug web and Android APK builds pass
with existing WebAssembly/Kotlin-plugin warnings. Tests cover UTC/null boundaries,
picker cancellation/disposal, exact manual reviews, account/member/week changes,
acknowledgement/uncertain-write recovery, dated hints, stale confirmations,
seven-day spacing, final-week overflow and mobile/large-text date controls.

The rebuilt browser app exposes the logged-out fallback for protected scheduling
links. Firestore at localhost:8085 remains unreachable from the integrated browser,
so authenticated date-picker/write/reload flows have not been certified with the
real Flutter SDK. Existing emulator data was not cleared. Physical-device and
production QA remain separate gates. Preview: `http://localhost:8790`.

### Firebase assignment-reader continuity - 2026-10-15

Authorized assignment content now exposes separate bookmarks for each original
chapter, including combined units. The toolbar's **Save assignment reading
position** records an explicitly chosen position. **My reading tasks** offers
**Continue saved assignment** and a clear-pointer action, independent of the
currently selected task page.

- Bookmarks reuse installation-wide preferences, shared across accounts and with
	the standalone/default reader. Bookmarking never writes completion or streaks.
- Assignment resume is separate from the standalone resume keys: one JSON value
	per Firebase UID, containing only account/group/assignee/week/canonical-unit,
	requested language and a finite relative position in 0-1. No scripture, private
	profile data or Firestore document is copied into this record.
- A save or clear updates confirmed UI state only after local storage acknowledges
	it. Failed writes retain the preceding confirmed UI pointer; invalid records expose no
	resumable assignment and remain clearable. Delayed account results are discarded.
	Already-dispatched local writes cannot be cancelled, but use the originating
	account's key and cannot overwrite the replacement account's pointer.
- Continue selects the saved reader language and opens the exact encoded
	assignment route. It does not authorize content: fresh server access is still
	required, even for locally bundled text. Missing/revoked assignments do not
	show content or restore a position. Clearing deletes only the local pointer.
- Restoration waits for authorized content and layout, and checks account,
	full assignment identity, language and content-load generation. The reader uses
	one measured document so lazy scroll-extent estimates cannot distort fractions.
	Positions are approximate across font, viewport and content changes, not
	paragraph anchors. Opening, scrolling and navigating never save automatically.
- Account-scoped local metadata is **not encrypted or confidential against someone
	with device/browser access**. Logout does not erase saved pointers. Neither
	bookmarks nor resume is cloud-synced, and no full history log is implemented.

Validation: **2,090 Flutter tests pass**, including 38 added continuity checks.
Touched source analysis reports no issues; Firebase debug web and Android APK
builds pass with existing WebAssembly/Kotlin-plugin warnings. Checks cover strict
metadata, persistence acknowledgements, combined originals, account replacement,
language/scope mismatch, delayed content/storage, revoked access, exact task links,
highlight regressions and narrow/large-text layout.

The rebuilt workspace renders and mobile logged-out assignment links return to
the root without reader content. Browser Auth on 9099 is reachable, but Firestore
8085 still returns connection refused; the newly shared 8087 page also refuses
connections. Authenticated Flutter SDK resume/bookmark flows and physical-device
QA therefore remain unverified. No emulator fixtures were cleared, rules changed,
cloud resources created or default-backend switch made. Preview:
`http://localhost:8790`.

For the Firebase-only backend goal, see the
[backend exit checklist](../firebase/README.md#firebase-only-backend-exit-checklist).

### Firebase trusted-feed backend foundation - 2026-10-15

Live-darshan and festival fetching now have emulator-only Firebase HTTP Functions,
with fixed upstream sources, explicit cache freshness and safe failure responses.
The Flutter integration is completed in the next milestone below. No Flutter
source/default-backend,
Firestore rules, fixtures, deployment or billing changed in this backend slice.

Validation: 96 Node 22 source/cache/HTTP/configuration/credential-isolation checks
pass; real emulator HTTP guard checks and successful live reads were observed.
The stream source is intermittent and may return safe 502, never expired cached
stream success. Festivals preserve actual source dates, including the current
four-column table. Browser playback/device QA and production/durable caching are
not certified. The last Flutter result remains 2,090 passing tests; this suite
was not rerun for the backend-only change. See
[service contracts and launch instructions](../firebase/README.md#local-trusted-feed-functions).

### Firebase public live and festival feeds - 2026-10-15

Public `/live` and `/events` routes now connect to the local demo Functions on
port 5001, independently of legacy APIs, Auth and private profiles. Open them
from the Firebase workspace or audio hub. Start the separate Functions launcher
as documented above; existing Auth/Firestore emulators and data are unchanged.

The isolated Flutter gateway pins host/project/region/path, omits credentials,
rejects redirects and malformed payloads, and bounds reads to 15 seconds/256 KiB.
Live metadata must be current, with a safe HTTPS HLS URL; no expired stream or
legacy API fallback is used. The shared player HTML is now also bundled for
Android WebView use. Web iframe URLs contain only the local Functions endpoint,
never signed stream tokens. Refresh recreates the iframe; Android in-player
retry obtains a new native gateway response instead of reusing an expired URL.

The existing festival UI preserves calendar dates without timezone conversion
and shows source, fetched/fresh-until UTC times, explicit stale status and
truncation. Unknown source dates retain their labels; no dates are guessed.
Retries await an ordinary cached GET. A failure does not display a preceding
success as if it were a new or fresh response.

Validation: **2,117 Flutter tests pass**, with 27 new gateway/model/widget checks;
**116 selected Node 22 checks pass**, including 20 actual-player-script checks.
New Flutter code/tests analyze cleanly; reused screens retain existing style/
deprecation infos but no warnings/errors. Firebase debug web/APK builds pass.
Desktop/mobile browser screenshots show the real three-day festival calendar;
real live video played at 1280x720 with advancing time and nonblank pixel samples.
Chromium used the existing, visibly disclosed video-only audio-codec fallback.
Controlled browser 502/retry and zero legacy API requests were verified too.

Try the running local preview at `http://localhost:8790/#/events` or
`http://localhost:8790/#/live`. Keep hostname localhost for web Auth restoration.
Browser viewport checks are not Android device/WebView/audio certification.
Upstream availability, durable cache/production controls, group reminder delivery
and the final release cutover remain pending. No deploy/billing or new dependency.

### Firebase group reminder schedule storage - 2026-10-15

Open **Group reminder schedule** from a Firebase group, or navigate to
`/groups/{groupId}/reminder-schedule` with a ready session. Members get read-only
values; current admins/leads get weekday controls, native time pickers and an
escalation-intent toggle. A confirmation identifies the exact group, values,
timezone and expected revision before saving.

**Storage only. Notifications are not scheduled or sent.** This flow never calls
the legacy API or native notification service, requests permissions, guesses an
assignment Monday, polls, or changes personal reminder preferences.

The canonical Firestore document uses Monday-based offsets 0..6 and fixed
`Asia/Kolkata` weekly intent; its deadline must strictly follow its start. Missing
records show unsaved defaults and are not created on load. Confirmed transactional
saves preserve creation audit, increment revision and reload from the server.
Role/account changes, stale revisions and unconfirmed snapshots fail closed.
Uncertain saves retain a draft, require a server read, and offer explicit restore
instead of blind write retry. Acknowledged saves with failed reload retry the read.

Validation: **2,171 full-suite Flutter tests pass**, including **54 new
model/controller/widget/SDK-shaped tests**. New files analyze cleanly; debug web
and Android APK builds pass. Widgets cover confirmation cancellation, signout
during confirmation, missing/member views, ordering, native pickers and 320px
double-sized text. Eight separate real-emulator tests validate rules without
clearing session fixtures; 49 selected Node checks pass overall.

The rebuilt browser verifies the logged-out route guard at
`http://localhost:8790`. Firestore port 8085 remains unreachable from the browser,
so authenticated Flutter SDK editing and Android device behavior remain QA gates.
No cloud deployment, release/backend switch, fixture clearing or dependency
change. See the [storage contract and delivery boundaries](../firebase/README.md#group-reminder-schedule-storage---2026-10-15).

### Firebase Android device reminders - 2026-10-15

The personal reminder screen now includes a separate **This device** section on
Android Firebase debug builds. Saving cloud preferences or a group schedule does
not enable delivery. Explicit device confirmation requests Android notification
permission; ordinary loads, refreshes and setting saves never request permission.
Web retains preference/schedule storage without invoking the native delivery driver.

- Save personal reading/verse preferences first, then explicitly enable this
	device. Verse reminders use the saved India time and seven rotating future
	dates. Only the next 64 chronological slots are queued; skipped/deferred counts
	are visible. Refreshing a verified opted-in queue does not request permission.
- Reading reminders require explicit per-device group/week registration and a
	confirmed Monday midnight in `Asia/Kolkata`. At most eight weeks are stored.
	Undated, outside-week and completed assignments are skipped; no Monday is
	inferred from an assignment. Existing initial/escalation times are respected.
- Server reads reverify the actual UID, preferences, membership, schedule and own
	assignments. Progress, settings, scheduling and departure operations pause and
	reconcile the queue. App resume refreshes after a private session is observed.
	Startup clears old slots before reauthorization; signed-out/account-switch
	cleanup requires an explicit new device opt-in for the next account.
- Stable IDs use a reserved range, not Dart `hashCode`. A local journal is written
	before scheduling so partial failures/crashes can be recovered. Cleanup targets
	only Firebase-owned IDs; legacy notifications are not canceled. Local opt-in,
	registered weeks and the journal are installation-local, not encrypted or synced.
- Permission revocation/server failures fail closed. Cancellation failures are
	reported as unverified, with an explicit Disable retry; they are not called a
	successfully paused queue. This is inexact local delivery, not FCM/background
	server synchronization or guaranteed delivery under Android battery/force-stop.

Validation: **2,203 full-suite Flutter tests pass**, including 32 new planner,
driver-double, controller and widget checks. Eight new files analyze cleanly;
Firebase debug web/APK builds pass. Widget checks cover permission confirmation,
signout during confirmation and 320px/double-sized text. Plugin doubles do not
certify physical Android delivery, reboot or OS restrictions; those remain QA
gates. The prior browser Firestore-8085 blocker was not rechecked in this increment.
No Functions/rules/data migration, fixture clearing, dependency, deployment or
default-backend change. Group archive followed in the milestone below;
assignment/account lifecycle and phone/social/Saptah tracks remain pending.

### Firebase group archive and restore - 2026-10-15

- Actual group admins can confirm Archive or Restore from group details.
	Revision and exact server Timestamp checks reject stale confirmations;
	account/role changes and SDK retries recheck authority. Uncertain writes
	require manual verification rather than blind retry.
- Current members keep discovery, reading, rosters, history and existing
	member/admin-scoped reads. Archived groups show read-only state. Content,
	progress, reports/moderation, membership/departure, invite, settings and
	schedule writes are denied; restoration is the only group mutation allowed.
	Private profile and personal preference editing remain independent.
- Existing groups need no backfill. Optional lifecycle metadata is all-or-none,
	revisioned and server-audited. Archive/restore cannot be batched with ordinary
	writes, and restoration does not recreate departed memberships or extend invites.
- Android cancels archived-group reading slots during local lifecycle operations
	or the next verified refresh/resume, preserving independent daily verses.
	Other clients are not guaranteed a push refresh or immediate offline cancellation.
	No historical records are deleted, reassigned or silently reactivated.

Validation: **2,218 full-suite Flutter tests pass** (15 new), including archive
confirmation/cancel/account changes, 320px double-sized text, readable history,
denied SDK mutations and device queue reconciliation. **16 non-clearing emulator
rule tests pass**, eight archive plus eight reminder checks, including the
48-write/12-target scheduling ceiling. Firebase debug web
and APK builds pass. Scoped analysis has no errors/warnings and six Riverpod
deprecation infos. Actual authenticated browser/device QA and physical Android
delivery remain gates; the existing browser Firestore-8085 blocker was not
rechecked. No fixture clearing, deployment, dependencies or default switch.

### Firebase assignment and membership history - 2026-10-15

- Assignment actions now include Archive, Reassign, Create fresh active version
	and a server-only retained-version inspector. Admins/leads confirm exact
	group/member/week/unit/version. Archive preserves status/date; fresh work
	resets progress and requires an explicit date or no date. Reassignment is
	atomic and refuses to overwrite any existing target assignment.
- Group admins can review an exact departed UID and explicitly confirm
	restoration. One transaction retains the prior departure, creates ordinary
	membership and discovery with fresh server joinedAt, and never restores former
	roles or shared names. Repeated departure/restoration cycles preserve history.
- Archived and pre-rejoin assignments stay readable history, not active tasks,
	group-progress totals, status controls or reminder work. Exact timestamps
	preserve even nanosecond join/version boundaries. New active work requires
	an explicit fresh assignment version; invitations/ordinary add cannot bypass it.
- Lifecycle dialogs close on account/role changes, support narrow large-text
	layouts and retain acknowledgment separately from a failed server reload.
	No automatic resend or historical erasure is performed.

Verified: **2,254 Flutter tests** (36 new), **22 non-clearing emulator tests**,
debug web/APK builds. Scoped source/test analysis has no errors/warnings and
four existing Riverpod deprecation infos. Actual authenticated Flutter SDK/device
QA, the existing browser Firestore-8085 forwarding blocker and physical Android
delivery remain unverified. FastAPI stays default; no deployment, fixture
clearing, dependency changes, permanent deletion, commit or push.

## Main flows (FastAPI mode, `BACKEND_MODE=fastapi`)

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
