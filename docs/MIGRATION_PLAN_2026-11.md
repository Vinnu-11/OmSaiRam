# What we're doing

Migrate the three remaining implementation areas in verified increments:
Android opt-in reminder delivery, reversible lifecycle operations, and expanded
Firebase feature parity. Include phone/Google/Apple SDK flows and currently
unsupported scheduling modes, without treating emulator success as production
provider certification. Build on the completed group reminder storage slice;
FastAPI stays the default until a separately approved production cutover.

# Steps

1. [x] Add a pure Firebase reminder planner: explicit confirmed week anchors,
   Asia/Kolkata times, future own-assignment slots, stable UID/group/week/unit IDs,
   daily verses and bounded queues. Skip undated/ambiguous or completed work.
2. [x] Connect Android permission/opt-in and scheduling through the existing
   plugin; reconcile/cancel on progress, settings, logout and lifecycle changes.
   Persist the owned notification ledger; web remains storage-only.
3. [x] Add revisioned group archive/restore contracts, rules and Flutter actions;
   retain historical data and make every affected access path respect archive state.
4. [x] Add reversible assignment archive/reassignment and membership restoration
   with explicit history/version boundaries; reconcile discovery, progress and reminders.
5. [x] Add reversible account deactivation/restore, blocked while group ownership
   is unresolved; support explicit ownership transfer without orphaning groups.
   Do not claim soft deactivation is Firebase Auth deletion or data erasure.
6. [x] Connect Firebase phone, Google and Apple sign-in/explicit credential linking,
   profile onboarding and cancellation/retry; preserve UID isolation and reject
   automatic email-based merging. Test emulator credentials; document provider setup.
7. [x] Migrate Saptah and remaining legacy-supported scheduling/hint modes with
   explicit dates, preview/confirmation and bounded atomic commits; finish the
   three tracks with isolated rules tests, full Flutter checks and web/APK builds.
   Owner decisions (2026-11-22): Saptah is a label only and shares the weekly
   scheduling; extend_last/round_robin finish the book in the last planned week.

Launch scope approved by the owner on 2026-11-22 (supersedes the matching
exclusions below): app name "Om Sai Sannidhi"; email, Google, phone and Apple
sign-in; Firebase becomes the default backend.

8. [x] Permanent self-service account deletion: delete the Auth account and the
   private profile/settings; group content stays under an anonymous UID; blocked
   while the account owns groups. In-app flow plus a public deletion-request page.
9. [x] Production Firebase mode for release builds from build-time project
   configuration (no emulator fallback), and Firebase as the default backend.
   FastAPI stays selectable with `BACKEND_MODE=fastapi`.
10. [x] Launch readiness: app name, Android release identity/signing hooks,
    rules/index deployment config, privacy and deletion pages, and one owner
    checklist for the steps only the owner can do (project, keys, Play Console).
    See [docs/LAUNCH_CHECKLIST.md](docs/LAUNCH_CHECKLIST.md). The application ID
    is still `com.example.om_sai_ram`: the owner has not chosen one.
11. [x] UI pass for devotees aged about 40 to 90 (approved 2026-11-22): "Temple
    at dawn" theme, language choice on first open, text-size button, new home
    with diya, daily teaching and large tiles, Naam Jaap 108-bead counter,
    separate sign-in / My account screen, plainer reading screen. Wording inside
    the group screens is a later pass.

# What we're NOT doing

- No FCM/server jobs, cascade erasure of group content, silent rejoin/history
  inheritance, automatic account merging or guessed assignment/week dates.
- No real SMS charges, secrets collection, cloud deployment/billing by the agent,
  SQL-data import or commits/pushes. The owner creates the project and deploys.
- No fixture clearing or reverting concurrent edits. Preserve the recent player
  and reminder changes; reuse existing SDK, plugin and Material/Riverpod patterns.
- No guarantee of delivery under Android force-stop/battery restrictions, iOS
  support or real-provider certification without the necessary configuration/devices.

# How we'll know it works

- Planner/plugin tests prove correct times, stable IDs, denied permissions and
  cancellation across accounts; real Android delivery remains a separately recorded gate.
- Non-clearing isolated emulator tests prove archive/restore, ownership/history,
  auth and scheduling boundaries, including raw bypass and stale/concurrent writes.
- Each increment gets focused validation before the next; full regression,
  scoped analysis and debug builds pass. Distinguish SDK doubles/emulator evidence
  from real SMS/OAuth/device QA and the existing browser Firestore-8085 blocker.

Reminder track verified: 2,203 Flutter tests (32 new), clean analysis of eight new
files, Firebase debug web/APK builds. Physical Android delivery is not certified.
Group archive/restore verified: 2,218 Flutter tests, 16 non-clearing emulator
rule tests, debug web/APK builds and scoped analysis with no errors/warnings
(six Riverpod deprecation infos). Members retain read-only access; admins restore.
Assignment/membership lifecycle verified: 2,254 Flutter tests (36 new), 22
non-clearing emulator rule tests, debug web/APK builds; scoped analysis has no
errors/warnings and four existing Riverpod deprecation infos. Immutable
before-images retain history; replacement resets progress and uses an explicit
new date or no date. Admin restoration creates fresh ordinary membership and
discovery. Exact join timestamps exclude old work from active progress/tasks/
reminders. Next: ownership transfer and reversible account lifecycle (step 5).
Ownership/account lifecycle verified (2026-11-22): 2,291 Flutter tests (22 new),
full emulator suite 366/366 on fresh emulators (6 new account tests; four stale
fixtures realigned: 17-item atomic content budget after the archive guard, and
owner-based departure wording). Deactivation is a soft, self-reversible
`deactivatedAt` marker on the private profile; rules block joins/adds/restores/
transfers into a deactivated account, while the owned-group precondition is a
client-side index scan (rules cannot enumerate groups). Not Auth deletion or
erasure. Next: step 6.
Provider sign-in verified (2026-11-22): 2,320 Flutter tests (29 new), emulator
suite 370/370 including four Auth-emulator credential tests (Google/Apple test ID
tokens, emulator SMS codes). Sign-in and explicit linking use the existing
`firebase_auth`/`google_sign_in` packages; new accounts continue to the explicit
display-name step; conflicting emails and already-used credentials are refused,
never merged. Real Google/Apple consent, SMS delivery and Android OAuth
configuration need the owner's Firebase project and are not certified. Next: step 7.
Scheduling parity verified (2026-11-22): 2,357 Flutter tests, emulator suite
376/376 on three consecutive fresh runs. Saptah-labelled groups can be created,
edited and scheduled weekly; extend_last/round_robin are defined for the
independent mode. Custom hint steps stay unsupported. Next: step 8.
Launch steps verified (2026-11-22): 2,368 Flutter tests, emulator suite 379/379,
75 Functions tests; debug and release web builds and debug and release APK builds
(release builds used placeholder project identifiers and the debug signing
fallback). Account deletion refuses a sign-in older than five minutes before
removing anything; archived groups keep an anonymous membership. Not done and
not claimed: any run against a real Firebase project or physical device, real
Google/Apple/SMS sign-in, rule deployment, store upload, or a UI pass.
UI pass verified (2026-11-22): 2,383 Flutter tests (15 new: contrast, first-open
language, text size, 320/412/1024 px at double text size, Naam Jaap), analysis
with no errors or warnings, debug web and APK builds, and a real-browser
click-through of home, language, text size, Naam Jaap, reading and email sign-up
against the Auth emulator. Not verified: signed-in group screens in a browser
(Firestore emulator port unreachable from the browser), any physical phone,
native-speaker review of the Hindi/Marathi/Telugu home wording.