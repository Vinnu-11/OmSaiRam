# Om Sai Ram — Software Requirements Specification

| Document attribute | Value |
|---|---|
| Version | 1.0 |
| Prepared | 2026-10-13 |
| Status | Draft for product-owner, engineering and QA review |
| Product | Om Sai Ram — individual and group Shri Sai Satcharita reading |
| Baseline | Checked-in application, existing user guide and QA catalogue |
| Approval | Not yet recorded; this document does not establish stakeholder sign-off or release certification |

## Contents

1. [Purpose and objectives](#purpose-and-objectives)
2. [Scope and release boundaries](#scope-and-release-boundaries)
3. [Stakeholders and permissions](#stakeholders-and-permissions)
4. [Definitions and requirement conventions](#definitions-and-requirement-conventions)
5. [Business rules](#business-rules)
6. [Functional requirements](#functional-requirements)
7. [Data and interface requirements](#data-and-interface-requirements)
8. [Nonfunctional requirements](#nonfunctional-requirements)
9. [Primary acceptance scenarios](#primary-acceptance-scenarios)
10. [Dependencies, gaps and open decisions](#dependencies-gaps-and-open-decisions)
11. [Verification and release acceptance](#verification-and-release-acceptance)
12. [Change control and approval](#change-control-and-approval)

## Purpose and objectives

This specification defines what the project must provide and how its delivery is accepted. It separates existing behavior from desired safety properties and incomplete integrations. It is not an assertion that every requirement is implemented, tested or approved.

### Product objectives

- Make scripture reading accessible without mandatory registration, including offline bundled text.
- Help groups coordinate weekly readings through both manual and automatic assignment.
- Assign combined chapters as one reading, avoiding repeated translated content across weeks.
- Let each participant report their own reading progress while protecting group data.
- Support multilingual reading, optional audio, devotional information and reminders without compromising core reading when an external service fails.
- Provide a maintainable, testable application with honest capability and platform claims.

### Related documents

- [User guide](USER_GUIDE.md): operational behavior and user-facing limitations.
- [QA test plan and cases](QA_TEST_CASES.md): 243 base cases and execution/reporting process.
- [Project overview](../README.md), [Flutter documentation](../om_sai_ram/README.md), [backend documentation](../backend/README.md): implementation and setup references.

These references describe the present baseline. Where a new requirement requires a behavior change, the gap and approval decision must be recorded rather than assumed delivered.

## Scope and release boundaries

### In scope

Public navigation/dashboard; email authentication and sessions; profile and account deletion; group membership and roles; manual/automatic reading assignment; combined chapter handling; reader and local preferences/history; group progress; chat/highlight API and display; audio/live stream; festival/programme/FAQ information; local-device reminders; localization; secure API/data handling; release verification.

### Platform baseline

| Platform | Scope |
|---|---|
| Android phone/tablet | Checked-in target; certify supported OS/device sizes, permissions, release audio and local reminders |
| Web | Checked-in target; certify release hosting, browser routing, API origins, streaming and responsive layouts |
| iOS/iPadOS | Conditional future release; platform files, signing, plugin setup and device certification required |
| Linux/other desktop | Conditional future release; platform/toolchain/plugin certification required |

Checked-in files establish a target, not proof of platform support. Exact minimum OS/browser versions require approval under DEC-01.

### Not committed in the current baseline

- Production SMS delivery and cryptographically verified Google/Apple login.
- Password reset, server-push notifications, WebSocket chat or guaranteed instant synchronization.
- Cloud synchronization of personal bookmarks/preferences/standalone reading history.
- A separate seven-day Saptah scheduling algorithm solely because a group has that mode label.
- Automatic migration of previously saved split-range assignments.
- Payments, subscriptions, advertisements, public social networking or administrative analytics.

Future integrations may be approved independently; their visible controls must not imply readiness before acceptance.

## Stakeholders and permissions

| Stakeholder | Need / responsibility |
|---|---|
| Guest reader | Public scripture, audio/information access without an account |
| Registered participant | Join groups, read assigned units, maintain own profile and status |
| Group lead | Coordinate assignments, ordinary membership, discussion and reminders |
| Group admin | Own group settings, roles, membership and destructive group actions |
| Product/content owner | Approve scope, chapter mapping, language quality, policies and release claims |
| Engineering/operations | Implement requirements, protect data, deploy and recover services |
| QA/accessibility reviewers | Verify requirements on actual roles, data, release builds and target devices |

Group roles are scoped per group; an admin in one group has no additional permission in another. Operations personnel are not automatically application group admins.

| Action | Guest | Authenticated outsider | Member | Lead | Admin |
|---|---|---|---|---|---|
| Public reader/media/information | Allowed | Allowed | Allowed | Allowed | Allowed |
| Create group / join by invite | Login first | Allowed | Allowed | Allowed | Allowed |
| Read private group data | Denied | Denied | Allowed | Allowed | Allowed |
| Assign/suggest/advance week/delete assignments | Denied | Denied | Denied | Allowed | Allowed |
| Add/search users; remove ordinary members | Denied | Denied | Denied | Allowed | Allowed |
| Remove another lead | Denied | Denied | Denied | Denied | Allowed |
| Change settings/roles/delete group | Denied | Denied | Denied | Denied | Allowed |
| Update reading status | Denied | Denied | Own only | Own only | Own only |
| Send group message/highlight | Denied | Denied | Allowed | Allowed | Allowed |
| Delete message/highlight | Denied | Denied | Own only | Any in group | Any in group |
| Configure group reminder settings | Denied | Denied | Denied | Allowed | Allowed |
| Leave group | Not applicable | Not applicable | Allowed | Allowed | Blocked while admin |

No role may remove itself or an admin through member-removal operations. Account deletion is blocked while the account is admin of any group. API enforcement is authoritative; client visibility must reflect the same rules.

## Definitions and requirement conventions

| Term | Definition |
|---|---|
| Original chapter / adhyaya | One numbered chapter in the Marathi original, 1–53 |
| Reading unit | One assignable singleton or combined range; 48 units total |
| Bundled entry | One JSON content entry; 53 Marathi entries, 47 per current translation |
| Assignment | One group/member/week/reading-unit record and associated reading status |
| Current week | Group's positive numbered reading week, separate from a viewed week |
| Scheduled date | Date associated with the reading week, normally its Monday |
| Local progress | Installation/browser-stored personal history; distinct from server group progress |
| Server chapter ID | Database key; not interchangeable with original number or bundled ID |

**Normative wording:** “shall” states a requirement. “May” is optional. “Current baseline” describes observed behavior, not approval of every limitation.

**Priority:** Must = core acceptance/safety; Should = important capability or quality; Conditional = required only if that integration/platform is included in the release. These priorities do not replace QA P0/P1/P2 classifications.

Known implementation gaps do not weaken a Must requirement: a reproducible violation remains a failure. An open decision blocks only the acceptance judgment that depends on missing scope/threshold semantics, not unrelated security, validation or integrity checks. Acceptance scenarios apply to approved release scope; including a Should capability in a scenario does not silently promote its priority.

Requirement identifiers are stable. The QA column lists representative test IDs/families, not a claim of exhaustive coverage or completed execution. All specified safety properties need verification even where current implementation has gaps.

## Business rules

| ID | Rule |
|---|---|
| BR-01 | Original Marathi numbering shall remain 1–53; translated entry counts shall not redefine original numbers. |
| BR-02 | Group units shall combine 16–17, 18–19, 43–44 and 51–53 once each. All other originals, including 50, remain singleton group units, giving 48 units. |
| BR-03 | A request for an interior number 17/19/44/52/53 shall normalize to unit start 16/18/43/51 respectively. Labels shall expose the entire range. |
| BR-04 | A translated combined body shall be read once. A Marathi group unit shall include all originals once; standalone Marathi shall keep separate originals. |
| BR-05 | One member/group/week shall have at most one assignment per reading unit, including legacy interior references and concurrent requests. Different members/groups/weeks may read the same unit. |
| BR-06 | Scheduling steps and readings-per-week shall count units, never individual numbers inside a combined range. |
| BR-07 | Valid statuses shall be `not_started`, `in_progress`, `completed`; the assignee may change status, including reverting a completed status. No admin/lead override is granted. |
| BR-08 | Group creation shall add its creator as admin; invite/direct joins shall add ordinary members. Roles shall be checked for every protected operation. |
| BR-09 | Missing explicit manual date shall resolve to the reference Monday plus selected-week minus current-week offset. Explicit dates shall be preserved. Automatic dates currently derive from the reference Monday. |
| BR-10 | Existing saved assignments shall not be silently rewritten when mappings/settings/membership change. Future regeneration and completed-history handling shall require a deliberate review. |
| BR-11 | Text unavailable as a translated standalone adhyaya, including 50, shall use Marathi fallback where present or a clear not-found outcome. |
| BR-12 | App-language changes shall initially synchronize reader language; a later reader-only change shall not alter app language. |
| BR-13 | Original numbers, server IDs, display ranges, bundled entries and reading-unit positions shall remain distinct throughout APIs, readers and scheduling. |
| BR-14 | Browser/native, offline/network and implemented/conditional capabilities shall be accurately disclosed; unsupported integrations shall not be represented as working. |

## Functional requirements

### Public access and navigation

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-NAV-01 | Must | The app shall allow guest access to home, bundled reader, audio/live, events, programme and FAQ; Groups/Profile shall require login. | NAV-01, NAV-03, NAV-04 |
| FR-NAV-02 | Must | The app shall handle protected/public deep links, invalid destinations and login/logout redirects without exposing private data or crashing. | NAV-05–09 |
| FR-NAV-03 | Should | Navigation shall provide consistent tab/back behavior, cancelable dialogs and dashboard counts reflecting their stated local/server sources. | NAV-06, NAV-10–12 |

### Authentication and profiles

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-AUTH-01 | Must | The system shall register unique email accounts, normalize login identifiers, validate names/email/password and return only the intended public profile and session tokens. | AUTH-01–07 |
| FR-AUTH-02 | Must | Email login shall return a generic failure for invalid credentials and apply configured failure throttling. | AUTH-08–11 |
| FR-AUTH-03 | Must | Protected APIs shall validate signed access JWTs, type, expiry and active account; refresh shall accept only valid refresh JWTs. | AUTH-12–14, AUTH-16 |
| FR-AUTH-04 | Must | The client shall restore valid sessions, refresh/retry eligible expired requests and clear authentication on terminal session expiry/logout without retry loops. | NAV-02, AUTH-13–15, AUTH-18 |
| FR-AUTH-05 | Must | Users shall edit their own permitted profile fields; duplicate identifiers, invalid input and clearing their active login identifier shall be rejected. | PROFILE-01–03 |
| FR-AUTH-06 | Must | Email users shall change passwords with their correct current password; phone-only users shall not use that flow. | PROFILE-04–05 |
| FR-AUTH-07 | Must | Eligible account deletion shall remove memberships/assignments, anonymize personal fields and reject old tokens while retaining safe historic references. Admin ownership shall block deletion until resolved. | PROFILE-08–10, CHAT-11 |
| FR-AUTH-08 | Conditional | Production phone login shall deliver OTPs through an approved sender, enforce single-use/expiry/throttling and complete the new-user name flow safely. | OTP-01–10 |
| FR-AUTH-09 | Conditional | Offered production Google/Apple login shall cryptographically verify provider identity/audience/expiry before issuing app tokens; incomplete integrations shall be disabled or clearly unavailable. | AUTH-19–20, SEC-05 |

### Group management

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-GRP-01 | Must | Authenticated users shall create a group with name, optional description, configured mode, readings/week and start; creator membership/invite creation shall be consistent. | GRP-01–04 |
| FR-GRP-02 | Must | Users shall join by a normalized valid invite code; repeated joins and nonexistent groups shall not create duplicate/ghost membership. | GRP-05–07 |
| FR-GRP-03 | Should | Members shall view their groups and private details; invite copy/share shall exclude tokens and handle cancellation/fallback. | GRP-04, GRP-08 |
| FR-GRP-04 | Must | Admin-only settings/role changes/deletion and lead membership actions shall follow the permissions matrix, including self/admin/lead-removal restrictions. | GRP-09–15 |
| FR-GRP-05 | Must | Leaving/removal/deletion shall revoke access and reconcile assignments/progress/dependent records according to approved retention rules without orphan records. | GRP-14–18, PROG-10 |
| FR-GRP-06 | Should | Authorized member lookup shall exclude existing members, cap results and mask contacts where required; ordinary members/outsiders shall not access it. | GRP-12–13 |

### Manual reading assignments

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-MAN-01 | Must | Admins/leads shall access Manual Assign from empty and populated schedules, independently of Auto-Schedule. | MAN-01–02 |
| FR-MAN-02 | Must | The form shall select a member and positive reading week, search chapters and select one/multiple, including nonconsecutive units. | MAN-03, MAN-10–12 |
| FR-MAN-03 | Must | The picker shall fetch actual server chapter IDs, prefer the Marathi index and support an English-only legacy index; it shall never guess IDs from numbers. | MAN-06–07 |
| FR-MAN-04 | Must | Combined units shall appear once; backend normalization/duplicate rejection shall enforce BR-02–05; each new assignment shall have not-started progress. | MAN-04–05, MAN-08–09 |
| FR-MAN-05 | Must | Existing selections shall clear when member/week changes; already-assigned units shall be disabled for that member/week. | MAN-08, MAN-10 |
| FR-MAN-06 | Must | Invalid member/chapter/week/permission shall leave authoritative data unchanged; default/explicit dates shall follow BR-09. | MAN-11, MAN-13–14 |
| FR-MAN-07 | Must | Individually saved multi-choice requests shall report partial success, preserve unsaved choices and avoid resubmitting acknowledged successes on retry. | MAN-15–16 |
| FR-MAN-08 | Should | Retry/loading/validation and scrolling shall remain usable with slow networks, small screens, keyboard and large text. | MAN-07, MAN-16–17 |

### Automatic schedules and suggestions

Let s be the one-based starting **unit position**, k the zero-based week offset, i the zero-based member index, N the member count and W readings/member/week. Original numbers are resolved after unit-position arithmetic.

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-SCH-01 | Must | Independent mode shall start each member at `s + k*N*W + i*W`, allocating up to W consecutive units. | SCH-01, SCH-05 |
| FR-SCH-02 | Must | Rotating-window mode shall start at `s + (k+i)*W`; dense mode at `s + k*W + i`; synchronized mode at `s + k*W`. | SCH-02–05 |
| FR-SCH-03 | Must | Scheduling shall preserve combined units, stable member order, correct group weeks/dates and rerun deduplication; cycle shall wrap after 51–53 to 1. | COM-01–02, SCH-07–09, SCH-11–13 |
| FR-SCH-04 | Must | Manual/truncate remainder handling shall report unfilled slots without assigning nonexistent chapters. UI/results shall disclose insufficient units. | SCH-09–10 |
| FR-SCH-05 | Conditional | Extend-last/round-robin shall be offered as supported allocations only after their exact redistribution semantics are approved and implemented; otherwise disclose/disable unsupported behavior. | SCH-10; DEC-04 |
| FR-SCH-06 | Must | Suggestions shall accept valid position/start hints, calculate steps in units, label manual/computed slots and perform no assignment writes until confirmation. | SCH-14–16, SCH-18 |
| FR-SCH-07 | Must | Confirmed member/week/unit assignments shall equal the approved preview; custom-step fallback or differing later-week progression shall not silently alter it. | SCH-17 |
| FR-SCH-08 | Must | Viewing weeks shall not advance current week; authorized advancement shall increment once without rewriting saved assignments. | SCH-19–20 |
| FR-SCH-09 | Must | Concurrent assignment/advance operations shall preserve uniqueness and avoid lost updates/partial transactions on PostgreSQL. | MAN-18, SCH-20 |

### Reading, content and progress

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-READ-01 | Must | Bundled scripture shall load without login or network, preserve original numbering and follow combined/fallback rules in both standalone and group contexts. | READ-01, READ-06–07; COM |
| FR-READ-02 | Should | The reader shall support chapter-list search, bookmarks, bounded font controls, prev/next and local resume/history without repeating/skipping ranges. | READ-02–05, READ-10–12 |
| FR-READ-03 | Must | Group Marathi reading shall assemble every original in the assigned range exactly once; translated reading shall not duplicate the combined entry. | COM-03–07 |
| FR-READ-04 | Must | Per-language caches shall not mix responses; older/equal or shorter partial server books shall not replace full bundled content. | READ-08–09 |
| FR-READ-05 | Must | Group assignment status shall be server-backed and writable only by its assignee; standalone local reading shall not falsely complete group work. | PROG-01–03, READ-13 |
| FR-READ-06 | Should | Assigned-reading completion shall prompt once at approximately95% scroll where applicable, allow Later and clearly report progress/local-history/chat partial failures. | PROG-04–07 |
| FR-READ-07 | Must | Completion/deletion shall reconcile unit-wide local completion and relevant reminders; invalid/stale assignment operations shall fail safely. | COM-06, PROG-08–10 |

### Community and reminders

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-COMM-01 | Should | Group members shall post/view messages with correct identity/order; author/lead moderation and group isolation shall be enforced. | CHAT-01–06 |
| FR-COMM-02 | Should | Highlight API/display shall use real chapter IDs, validated text/comment/paragraph index and author/lead deletion. Full reader creation/navigation requires explicit UI acceptance. | CHAT-07–11 |
| FR-COMM-03 | Must | User text shall remain inert; refresh behavior shall not promise unavailable real-time delivery. | CHAT-06, CHAT-12 |
| FR-NOTIF-01 | Should | Supported native clients shall offer permission-aware daily reminder enable/disable/time settings without crashing unsupported platforms. | NOTIF-01–03, NOTIF-14 |
| FR-NOTIF-02 | Should | Admins/leads shall save per-group initial reminder/deadline/escalation settings; members may read them but not write. | NOTIF-04–05 |
| FR-NOTIF-03 | Must | Devices shall schedule only their current user's incomplete dated assignments, skipping past times and reconciling duplicate/stale reminders. | NOTIF-06–11 |
| FR-NOTIF-04 | Should | Escalation shall use72/48/24/12/6/2 hours before the deadline when enabled, and delivery shall follow approved device-local timezone/DST semantics. | NOTIF-07–08, NOTIF-12 |
| FR-NOTIF-05 | Must | Local scheduling and OS delivery constraints shall be disclosed; no server-push guarantee shall be inferred. Completion/deletion/logout/access revocation shall trigger required local cleanup. | NOTIF-09–14 |

### Media, information and localization

| ID | Priority | Requirement | QA reference |
|---|---|---|---|
| FR-MEDIA-01 | Should | The app shall present five aarti groups and catalogued chapter audio, with playable availability matching the selected language/unit. | MEDIA-01–03 |
| FR-MEDIA-02 | Should | Supported playback controls/lifecycle shall function; native completed chapter downloads may be reused offline and web shall stream without native filesystem dependency. | MEDIA-04–06, MEDIA-09–11 |
| FR-MEDIA-03 | Must | Download/cache/media failures shall not corrupt reader state or treat incomplete files as successfully cached. | MEDIA-07–08, MEDIA-12 |
| FR-INFO-01 | Should | Live discovery shall retrieve a fresh upstream URL and provide controlled upstream/codec/offline errors, refresh and supported playback lifecycle. | LIVE-01–06 |
| FR-INFO-02 | Should | Festivals shall use cached/refreshable upstream data; public programme/FAQ shall render safely with empty/error/offline states. | INFO-01–07 |
| FR-LANG-01 | Must | Language selection shall match approved available/beta flags, device-locale fallback and BR-12; no text/audio availability equivalence shall be assumed. | LANG-01–04, MEDIA-02 |
| FR-LANG-02 | Must | Native script/heading/body quality shall be reviewed by competent readers; disabled/beta languages and untranslated UI shall be disclosed accurately. | LANG-05–08, READ-14 |

## Data and interface requirements

### Data model and integrity

| ID | Priority | Requirement | Verification |
|---|---|---|---|
| DR-01 | Must | Users shall have unique normalized login identifiers where present; passwords/OTPs shall be hashed, personal responses shall exclude hashes. | AUTH, OTP, SEC-03 |
| DR-02 | Must | Membership shall represent group/user/role once; assignment identity shall include group, member, week and canonical unit. Concurrent uniqueness shall be enforceable, not assumed from UI. | GRP-18, MAN-18, SCH-20 |
| DR-03 | Must | Each assignment shall have at most one progress record; chapter references shall use valid database IDs and canonical metadata. | MAN, COM, PROG-03 |
| DR-04 | Must | Group/member/account deletion shall avoid orphan assignments, progress, notification settings and unsafe chat/highlight references; approved historical retention shall be explicit. | GRP-14–17, PROFILE-09 |
| DR-05 | Must | Personal local history/preferences shall disclose storage scope; shared-device account switching shall not expose prior private account data. Storage lifecycle must follow DEC-05. | AUTH-22, READ-11, SEC-12 |
| DR-06 | Must | Schema upgrades shall use reviewed migrations/backup procedures; startup table creation shall not be represented as migration of existing schemas. | OPS-01, OPS-04 |

Principal entities are User, Group, GroupMember, Chapter, ReadingAssignment, ReadingProgress, GroupMessage, ChapterHighlightComment, PhoneOtp, Festival and GroupNotificationSchedule. Local language/font/theme/bookmark/resume/history preferences and audio cache are distinct from server records.

### Interface contracts

| ID | Priority | Requirement | Verification |
|---|---|---|---|
| IR-01 | Must | The Flutter client shall use configurable API host/versioned JSON endpoints and bearer authentication; production hosting shall use HTTPS and explicit approved origins. | OPS-03, OPS-06, SEC-04/08 |
| IR-02 | Must | API responses shall provide controlled validation/auth/permission/not-found/throttling/upstream failures; clients shall recover without exposing tracebacks/secrets. | AUTH, MAN-13/15, LIVE-02, SEC-06 |
| IR-03 | Must | Assignment responses shall expose number/full range/end metadata; suggestions shall expose canonical numbers and full labels. | COM-09, SCH-18 |
| IR-04 | Should | Version/schema/endpoint documentation shall remain available and current; private methods shall not become public through client routing. | OPS-01, SEC-01 |
| IR-05 | Must | External provider/media failures shall be isolated from core offline reading; integrations shall be verified independently with controlled fixtures and real-service certification. | OTP-10, AUTH-19/20, MEDIA/LIVE, RES-09 |

### Current input/configuration boundaries

This table records present implementation constraints, not invented new product decisions. Inconsistencies require DEC-02 approval and coordinated client/API changes.

| Field | Present boundary |
|---|---|
| API name | Trimmed,1–255 characters |
| Group-name UI | Trimmed,2–80; generic required-field UI max100 |
| Password |8–128 characters; no configured complexity rule |
| Group description | Up to1000 characters |
| Group readings/week and start number |1–53 each; readings/week counts units |
| Current-week settings |1–10000; manual assignment week currently only constrained to ≥1 |
| Auto-schedule weeks ahead |1–12 |
| Invite | Generated6 characters; API4–8; UI4–20 |
| OTP | Generated6 digits,10-minute expiry; UI numeric4–8; API length4–8 |
| Chat/comment | Trimmed1–2000; highlighted text1–500; paragraph index ≥0 |
| Message page size |1–100; default50 |
| Reminder day/hour/minute |0–6 /0–23 /0–59 |
| Access/refresh lifetime defaults |30 minutes /7 days; configurable |
| Failure/send limits | Login10 failures/15 minutes; OTP send5/hour; OTP verification5 failures/10 minutes; currently process-local |

## Nonfunctional requirements

| ID | Priority | Requirement and acceptance measure | QA reference |
|---|---|---|---|
| NFR-SEC-01 | Must | Authorization shall be enforced per object and operation on the server, including role revocation and cross-group ID substitution. No unauthorized read/write is acceptable. | SEC-01–02, SEC-07 |
| NFR-SEC-02 | Must | Production credentials/tokens/OTPs shall not appear in URLs, client/server logs, analytics or shared content; approved secure storage/TLS shall be verified. | SEC-03–04, OTP-10 |
| NFR-SEC-03 | Must | Token replay/revocation and multi-worker abuse-control policy shall be approved and tested before release; process-local throttles/stateless JWTs shall not be overstated. | SEC-05/10, AUTH-17 |
| NFR-REL-01 | Must | Core offline text/local controls shall remain available when API/media fail; network writes shall not falsely claim persistence or silently queue unsupported operations. | RES-01–04 |
| NFR-REL-02 | Must | Retries/concurrent writes/app termination shall not produce corrupt identities, duplicate same-week units or orphan state. Failure recovery shall identify acknowledged partial writes. | RES-03/05/09, SEC-09 |
| NFR-UX-01 | Should | Critical flows shall remain usable on approved phones/tablets/web viewports, with keyboard and200% text scaling, without inaccessible actions or overflow. | A11Y-03/06, MAN-17 |
| NFR-A11Y-01 | Should | Target WCAG2.2 AA where applicable, keyboard/screen-reader operability, meaningful labels/focus/errors and non-color-only status; verify with human review. | A11Y-01–08 |
| NFR-CONTENT-01 | Must | Bundled text shall preserve complete approved chapter ordering/ownership without duplicated/missing passages; each release language needs competent content-review sign-off or clear beta/disabled designation. | READ-14, LANG-06/08 |
| NFR-PERF-01 | Should | Cold start, reader load/scroll, API latency, schedule size, media memory/battery and concurrent user load shall meet approved measurable budgets on named devices/datasets. Numeric budgets remain TBD under DEC-03, not implied guarantees. | RES-06–08, SCH-20 |
| NFR-OPS-01 | Must | Release deployments shall configure secrets/origins/API host, retain database data across restart and rehearse schema backup/restore/rollback without private-data exposure. RPO/RTO remain TBD under DEC-08. | OPS-01–06/10 |
| NFR-MAINT-01 | Should | Requirements, OpenAPI/user guidance and tests shall stay traceable; automated tests/analyzer findings shall be reviewed and deterministic suites shall isolate external network dependencies. | OPS-08–09 |
| NFR-COMPAT-01 | Must | Support claims shall match release-build certification for platform/browser/plugin capabilities, including web media registration and native permission/OS behavior. | OPS-05–09, MEDIA-06, NOTIF-13/14 |

## Primary acceptance scenarios

These scenarios are acceptance oracles, not records of passed tests.

### AC-01 — Manual group assignment

**Given** an admin/lead, registered member and populated server chapter index, **when** the lead selects that member, week3 and units1,16–17,20, **then** exactly those three assignments shall be saved using real server IDs, with not-started progress and the appropriate date. Reposting16 or17 for the same context shall not add a duplicate. Assigning it in week4 shall be allowed. Unauthorized members shall be denied. Verify FR-MAN and MAN-01/03/04/06/08/09/14.

### AC-02 — Combined weekly progression

**Given** one member and one unit/week, **when** four weeks are scheduled from15, **then** the units shall be15,16–17,18–19,20. Starting53 with two units and cycle shall produce51–53 then1. Marathi group content shall include all originals in each range once; standalone originals shall remain separate. Verify BR-01–06, COM-01–08 and SCH-08.

### AC-03 — Own progress and isolation

**Given** M1 owns an assignment in G1, **when** M1 completes it, **then** its server progress shall change and authorized members shall see the saved value after refresh. Admin/lead/M2 shall not alter M1's status, and outsider X shall not read G1's private data. Verify FR-READ-05/07, PROG-01/02 and SEC-01/02.

### AC-04 — Preview and confirmation consistency

**Given** multiple members and multiple future weeks, **when** the lead confirms a suggestion, **then** the saved member/week/unit grid shall equal the approved preview, including combined units and custom-step behavior. A silent fallback to a different distribution shall fail acceptance. Verify FR-SCH-06/07 and SCH-14–18; the current mismatch risk remains a gap.

### AC-05 — Offline reader and external failure

**Given** a fresh installation containing bundled books, **when** the network/API/media are unavailable, **then** bundled scripture and local controls shall remain usable; network-only writes shall report failure without claiming a save. Verify FR-READ-01, NFR-REL-01 and READ-06/RES-01/02.

### AC-06 — Safe session and deletion

**Given** an eligible account, **when** logout or deletion is confirmed, **then** local authentication/private reminders shall be cleared; deletion shall anonymize personal server data and deny old tokens. Admin ownership shall block deletion until resolved. Retained messages shall use anonymized identity. Verify FR-AUTH-04/07, AUTH-15, PROFILE-08–10 and CHAT-11; copied-token logout revocation needs DEC-06.

### AC-07 — Own device-local reminders

**Given** valid native permission, reminder settings and dated incomplete assignments, **when** the current member schedules reminders, **then** only their future reminders shall be queued, with whole-unit labels and approved timezone semantics. Completion/deletion/logout shall reconcile pending reminders. Verify FR-NOTIF, NOTIF-06–12; device-zone resolution is an outstanding acceptance risk.

## Dependencies, gaps and open decisions

### Dependencies and constraints

- Flutter/Dart and configured Android/web targets; native plugin and browser support vary.
- FastAPI/SQLAlchemy and PostgreSQL; SQLite automated tests do not certify production concurrency/cascades.
- Authorized scripture/media content sources and competent language reviewers; OCR boundaries are not automatically reliable.
- External official festival/live pages and audio hosts; HTML/URLs/codecs can change independently.
- Native OS permission/idle/battery behavior; reminders are local, not server push.
- Development OTP/provider placeholders must not be used as production-ready authentication.

### Current gaps affecting acceptance

| Gap | Requirement affected | Current baseline / required action |
|---|---|---|
| GAP-01 | FR-AUTH-08/09, NFR-SEC-02 | No production SMS sender/provider verification; OTP logging currently exposes plaintext codes. Implement/certify or remove unavailable flows from release scope; remove sensitive production logging before deployment. |
| GAP-02 | NFR-SEC-03 | Throttling process-local; copied JWT revocation/reuse policy incomplete; approve policy and suitable enforcement. |
| GAP-03 | FR-SCH-05/07 | Remainder redistribution and preview-confirm later-week/custom-step semantics require resolution and fixture tests. |
| GAP-04 | BR-05, FR-SCH-09, DR-02 | Application duplicate queries lack a unit-level concurrency guarantee; verify/enforce atomic uniqueness on PostgreSQL. |
| GAP-05 | FR-NOTIF-03/04 | Device timezone resolution and settings/assignment load ordering/cancellation need real-device verification and correction where necessary. |
| GAP-06 | DR-05 | Local settings/history not guaranteed account-separated; approve scope and implement private-data isolation as needed. |
| GAP-07 | NFR-CONTENT-01 | Beta OCR quality, untranslated UI and chapter boundaries need reviewed evidence per language. |
| GAP-08 | FR-GRP-05, DR-04 | Deletion/leave/remote-revocation cleanup needs PostgreSQL and device lifecycle verification; UI/backend role mismatches need reconciliation. |
| GAP-09 | NFR-COMPAT-01 | Android/web checked in but not blanket-certified; iOS/desktop require additional setup and separate approval. |
| GAP-10 | BR-10 | No automatic legacy split-assignment migration; supply reviewed future regeneration/history-preservation procedure. |

### Decisions requiring approval

| ID | Decision / deliverable | Suggested owner | Status |
|---|---|---|---|
| DEC-01 | Supported OS/browser/device matrix and release platform scope | Product + engineering + QA | Open |
| DEC-02 | Reconcile name/invite/OTP UI/API limits and practical upper bound for manual week/date | Product + API/client owners | Open |
| DEC-03 | Numeric startup/API/scroll/capacity/memory/battery performance budgets and benchmark dataset | Engineering + product | Open |
| DEC-04 | Exact extend-last/round-robin and custom-suggestion confirmation semantics | Product + group workflow owner | Open |
| DEC-05 | Account-versus-device preference/history policy, cache retention and shared-device privacy | Product + privacy owner | Open |
| DEC-06 | Logout/password-change token revocation, refresh reuse and distributed rate-limit policy | Security + backend owner | Open |
| DEC-07 | Enabled languages, beta labeling and content-review sign-off; highlight authoring and Saptah scope | Content + product | Open |
| DEC-08 | Availability target, retention, backup frequency, RPO/RTO and rollback procedure | Operations + product | Open |
| DEC-09 | SMS/social-provider readiness, costs, allowed providers and exposure of unavailable UI | Product + identity owner | Open |
| DEC-10 | Existing split-schedule migration, completed-history treatment and user communication | Product + backend owner | Open |
| DEC-11 | Device-local reminder timezone/refresh/remote cleanup policy and unsupported platforms | Product + client owner | Open |

Suggested owners are roles, not assigned individuals. Open decisions must be closed or explicitly deferred before the affected requirements are declared accepted.

### Verification dependencies

| Decision | Affected verification | Execution guidance |
|---|---|---|
| DEC-01 | OPS-05/09; platform-specific MEDIA/NOTIF/A11Y cases | Record the tested platform; block certification of an unapproved target, not existing-target tests. |
| DEC-02 | AUTH-02, GRP-02/06, OTP-06, MAN-11 | Verify current UI/API boundaries separately; attach discrepancy evidence. Acceptance of a unified future boundary awaits approval. |
| DEC-03 | RES-06–08, performance portion of SCH-20 | Collect measurements now; budget-based Pass/Fail awaits thresholds. Uniqueness/corruption checks remain executable. |
| DEC-04 | SCH-10, custom confirmation details | Redistribution semantics require approval; preview-versus-saved mismatch under SCH-17 remains a failure of FR-SCH-07. |
| DEC-05 | AUTH-22, READ-11, SEC-12 | Preference portability/retention awaits policy; exposure of prior private account data remains a privacy failure. |
| DEC-06 | AUTH-17, SEC-05/10 | Record actual token/replay/throttle behavior; production policy approval does not imply current enforcement. |
| DEC-07 | READ-14, LANG-06/08, GRP-03, CHAT-10 | Attach reviewer/language/date and approved-source evidence to the QA execution record; do not equate OCR presence with quality sign-off. |
| DEC-08–11 | OPS-04/09/10, COM-10, NOTIF-09–14, OTP-10, AUTH-19/20 | Record recovery/legacy/reminder/integration scope and explicit blockers; verify unaffected current flows normally. |

For per-endpoint public/authenticated/role access, use the [backend endpoint reference](../backend/README.md#endpoint-reference) together with this permissions matrix. Operational comments such as “admin/internal” do not override an endpoint's actual authorization contract.

## Verification and release acceptance

1. Link each delivered requirement to tests, release build/environment and observed evidence in the [QA catalogue](QA_TEST_CASES.md). Family references here expand to applicable cases and parameter combinations.
2. Execute role boundaries through direct APIs, not only hidden/disabled controls. Use PostgreSQL for transaction/cascade/concurrent-write acceptance.
3. Run unit/widget suites and analyzer checks; separately certify real browser/device notifications, external services and content quality.
4. Mark each requirement **Not verified**, **Accepted**, **Failed**, **Blocked** or **Deferred with approval**, with owner/build/evidence. Document presence is not acceptance.
5. All release-scope Must requirements and applicable QA P0 cases must pass. Unresolved security/data-loss/content-integrity/crash defects block release; other exceptions require recorded impact and approval.
6. Conditional integrations shall either be independently accepted or explicitly absent/unavailable in release claims. Performance/availability acceptance requires approved measurable targets.
7. Preserve known gaps and completed-history decisions in release notes/user guidance. Historical automated counts are not a coverage percentage or proof of requirement completeness.

## Change control and approval

Requirement changes shall record ID, reason, user impact, affected business rules/APIs/data migration, QA cases and documentation. Do not renumber existing IDs merely because rows move. Source behavior that contradicts an approved requirement shall be treated as a defect or an approved change, not a silent revision of acceptance criteria.

| Approver | Responsibility | Name/date/decision |
|---|---|---|
| Product owner | Scope, business rules, open product decisions | Pending |
| Engineering owner | Feasibility, data/API compatibility and gaps | Pending |
| QA owner | Testability, platform coverage and release evidence | Pending |
| Content/accessibility reviewers | Language integrity and usable reading | Pending |
| Security/operations owner | Identity/privacy, deployment and recovery policies | Pending |

### Revision history

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-10-13 | Initial draft based on repository behavior, manual/combined reading requirements and documented QA scope; approval and execution remain pending. |