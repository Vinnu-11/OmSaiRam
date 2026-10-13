# Om Sai Ram — User Guide

Updated: 2026-10-13. This guide describes the checked-in app, not a promise that every platform or external integration is production-certified.

For project scope, business rules and acceptance criteria, see the [requirements specification](REQUIREMENTS.md).

## Browse without an account

The home dashboard, scripture reader, audio, Live Darshan, daily programme, events and FAQ can be opened without signing in. Groups and profile settings require authentication.

## Sign in

- **Email:** Create an account with your name, valid email and an 8–128-character password, then sign in using the same email/password.
- **Phone:** Enter a valid phone number, request a code and verify it. New users are asked for a name before the account is created. Codes expire after 10 minutes and cannot be reused after successful verification.
- **Current phone limitation:** The backend logs test OTPs and has no production SMS sender. Actual SMS sign-in is unavailable until that integration is implemented. Do not put real phone numbers in a development environment.
- **Current social limitation:** Google/Apple controls exist in the client, but backend provider-token verification is incomplete. They must not be treated as working production sign-in methods merely because OAuth credentials are supplied.

Repeated failed attempts may be rate-limited. Password reset is not implemented. Never send a password, OTP or session token to another group member.

## Create or join a group

1. Open **Groups** after signing in.
2. Create a group with its name, optional description and reading mode, or join using an invite code.
3. The creator becomes an **admin**. A joined user becomes a **member**.
4. Copy/share the group invite code with intended participants. Group details and readings are visible only to group members.

The group can be labeled chapter-wise or Saptah. A Saptah label alone does not guarantee a separately implemented seven-day automatic plan; review the actual saved weekly assignments.

### Roles

| Role | Responsibilities |
|---|---|
| Admin | Assign readings, manage ordinary members/leads, edit group settings/roles, configure reminders and delete the group |
| Group lead | Assign readings, add/search/remove ordinary members, moderate chat/highlights, configure reminders and advance the reading week |
| Member | Read the group's schedule, complete their own assignments, participate in group chat and leave the group |

Only an admin can change roles/settings or delete the group. An admin/lead cannot complete another member's reading on their behalf. If a restricted control is visible, the server still enforces these permissions.

## Assign group readings manually

Available to admins and group leads, alongside automatic scheduling:

1. Open the group and select **Schedule**.
2. Select **Manual Assign**.
3. Choose the **member** and **week**; the currently displayed week is prefilled.
4. Search/select one or more chapters. Nonconsecutive choices are allowed.
5. Select **Assign**. Saved readings appear in the chosen week's schedule with **Not started** status.

Important behavior:

- Already-assigned readings for that member/week are disabled. A combined range counts as one reading.
- Changing the member or week clears the current chapter selection.
- The same reading can be assigned to different members, different groups or the same member in a later week.
- The server chooses that reading week's Monday when no explicit date is supplied, allowing reminders to use the saved date.
- Multiple choices are saved individually, not as an all-or-nothing batch. If a request fails partway through, the sheet shows the error and keeps unsaved choices for retry; successful choices are not resubmitted.
- Chapters are loaded from the server index. If unavailable, use **Retry**; offline manual assignment is not queued.

## Combined chapters

Group readings preserve original Marathi chapter numbers, but these units are assigned together:

| Displayed reading | Original chapters included |
|---|---|
| 16–17 | 16 and 17 |
| 18–19 | 18 and 19 |
| 43–44 | 43 and 44 |
| 51–53 | 51, 52 and 53 |

There are **53 original chapters** and **48 group reading units**. Translation books have **47 bundled entries** because chapter 50 is absent as a separate translation entry; the reader falls back to Marathi for it, and group scheduling keeps 50 as a separate unit.

Example with one member and one reading/week: **15 → 16–17 → 18–19 → 20**.

Translations read a combined entry once. A Marathi group assignment contains all corresponding original chapters together, with one group status. The standalone Marathi chapter list remains separate.

Previously saved schedules that split a range across weeks are not rewritten automatically. Ask the group admin/lead to review, remove affected future assignments and regenerate the future plan; agree how completed history should be preserved before deleting anything.

## Automatically schedule readings

Choose **Auto-Schedule**, starting chapter, weeks ahead, distribution mode and remainder behavior. All chapter counts below mean **reading units**, not individual numbers inside a combined range.

| Mode | Intended distribution |
|---|---|
| Non-overlapping / independent | Each member gets a different slice; the group advances by members × readings/week |
| Rotating Window | The window advances by readings/week; adjacent members take consecutive slices |
| Dense Sliding | Members start one reading apart, creating overlapping discussion readings |
| Synchronized | Everyone reads the same units each week |

**Cycle** wraps after 51–53 back to 1. Manual/truncate flags unfilled slots after the book ends. Extend-last and round-robin options require careful review of actual results; their labels are not evidence of correct remainder redistribution.

Smart Suggestions use manually entered starting hints to preview a pattern. Always compare the preview with saved readings after confirmation: multi-member later-week progression and custom-step confirmation are known verification risks. Do not assume a preview alone creates any assignments.

**Next Week** advances the group's current week. Week arrows only change the schedule being viewed. Advancing does not itself rewrite existing assignments.

## Read and complete an assignment

1. Open your assigned card in the group schedule.
2. Read the full chapter/range. Adjust text size or use available audio.
3. At approximately 95% scroll progress, a completion prompt may appear once.
4. Confirm completion or choose Later. You can also change your own status from the schedule where offered.

Statuses are **Not started**, **In progress** and **Completed**. Completing through the reader updates group progress, marks original chapters locally and attempts to post a completion message in the group. A network failure in a later part of that flow may require checking the saved status before retrying.

Other members see the saved status when their client refreshes; the app does not guarantee WebSocket-style instant synchronization. Reading a public/standalone chapter is not the same as completing a group assignment.

## Reader, languages and local settings

- Scripture text is bundled and available offline. Group changes, authentication and new server data need connectivity.
- Search the chapter list, bookmark chapters, adjust font size and use previous/next navigation.
- Language settings let you choose app and reader languages. Changing the app language initially synchronizes the reader; a separate reader selection can override it.
- Seventeen languages are selectable. Urdu content exists but its selection is disabled. Some other languages are labeled beta because OCR/content quality is incomplete.
- Font, dark mode, language, bookmarks and local reading history use device/browser storage. Do not assume cloud synchronization, survival after clearing storage or guaranteed account separation on a shared device.
- Background server updates do not replace a full bundled book with a shorter partial server copy.

## Audio and Live Darshan

- The audio section includes five daily aarti groups and chapter recordings for catalogued languages. Audio availability is not the same as text-language availability.
- Native chapter audio can be downloaded and then reused offline; web audio streams and needs a connection.
- Reader audio is shown only where a matching track exists. Network/source-file failures may prevent playback.
- Live Darshan requires connectivity, a reachable official upstream stream and a compatible browser/WebView. Autoplay can require a tap; some browsers lack required audio codecs and may use a video-only fallback.
- External media/events can change independently of this app.

## Chat and highlights

Members can send messages to their group. Authors can remove their own messages/highlight comments; admins/leads can moderate other entries in that group. Highlight comments are supported by the API and group display; verify the particular client creation/navigation flow before assuming all reader highlight affordances exist.

Refresh/loading behavior governs when another device sees a new message. Do not post personal passwords, OTPs or tokens in the chat.

## Reading reminders

- Profile settings offer a daily verse reminder on supported native devices.
- Admins/leads configure group reminder timing and reading deadlines in the Schedule tab.
- A member's device fetches those settings and schedules **local** reminders for its own pending readings.
- Escalation can include reminders 72, 48, 24, 12, 6 and 2 hours before the deadline, skipping times already passed.
- OS permission, battery/idle rules, opening/refetching the schedule and timezone behavior affect delivery. This is not server push or a guarantee that all devices immediately receive a newly configured reminder.
- Completing/deleting a reading and logging out should cancel relevant group reminders. Report stale reminders rather than assuming they disappear on every remote change.
- Browser/native notification support differs; device-local timezone/DST accuracy remains a test requirement.

## Profile, leaving and deletion

- Edit your profile, switch dark mode/languages and manage local daily reminders.
- Email accounts can change passwords using their current password. Phone-only accounts cannot use email password change.
- Ordinary members and leads can leave a group. Admins cannot leave while holding an admin role; arrange another admin and a permitted role change, or delete the group.
- Account deletion is blocked while admin of any group. Eligible deletion removes memberships/assignments and anonymizes personal account fields; historic messages/highlights retain an anonymized reference.
- Logout clears the client session; current stateless JWT behavior is not a promise of instant server revocation of every copied token.

## Troubleshooting

| Symptom | Check |
|---|---|
| Manual sheet has no chapters | API availability and seeded chapter index; Retry; ask admin to verify backend setup |
| Combined range appears in two old weeks | Review legacy assignments and regenerate future readings without deleting completed history accidentally |
| Permission error | Check actual group role; settings/role changes/deletion are admin-only |
| Phone code never arrives | Current backend has no real SMS sender; use only approved test setup |
| Google/Apple sign-in fails | Backend provider verification is not implemented; use email or approved test-phone flow |
| Reader works but group actions fail | Bundled text is offline; group operations need API connectivity/session |
| Audio/live unavailable | Network, external source, browser gesture/codec support and release-build configuration |
| Reminder missing/wrong time | OS permission, battery settings, group schedule refresh, own saved assignment date and device timezone |

For testing and defect reports see [QA plan and cases](QA_TEST_CASES.md). For installation/configuration see [project README](../README.md), [Flutter README](../om_sai_ram/README.md) and [backend README](../backend/README.md).