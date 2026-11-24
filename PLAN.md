# What we're doing

Make group study (the main feature) simple for devotees aged about 40 to 90 and
for group leads. Today the group screens show raw member IDs, 64-character
invite codes, technical wording and about 15 buttons on one page. We will
rebuild them around "this week's reading", show names everywhere, make joining
one tap, give leads the tools they need, and test it end to end in a browser.
It also closes the last migration gap the agent can close: Live Darshan and
festivals on Android without paid Cloud Functions.
The finished migration plan is kept in [docs/MIGRATION_PLAN_2026-11.md](docs/MIGRATION_PLAN_2026-11.md).

# Steps

1. [x] Feeds without billing: on Android, when no feed service is configured,
   the app reads the Live Darshan stream and the festival list directly from
   sai.org.in with the same checks as the Cloud Functions. Web still needs the
   deployed functions.
2. [x] Group list and group home: cards for my groups ("Week 3: chapters 5-6");
   separate "Start a new group" and "Join a group" screens. Group home shows
   my reading this week with Read and "I have read it" buttons, a "6 of 8 have
   read" summary, and big tiles for Chat, Shared quotes, Members, Reminders.
   Admin and lead tools move behind one "Manage group" button.
3. [x] Names instead of IDs: creating or joining a group shares my account name
   with that group (one-line notice; changeable under Members). Members, chat,
   shared quotes and progress show names; anyone without one shows as
   "Member 3". Raw IDs are no longer shown.
4. [x] Invites: one "Invite" button opens WhatsApp/SMS with a join link and an
   8-letter code (24-hour expiry, revocable). The join screen accepts the code,
   the link or the pasted message. Leads can invite too (rules change).
5. [x] Lead tools: "Plan the next weeks" in plain steps (members, chapters per
   person, number of weeks, preview in words, confirm); "Move to next week" for
   leads too (rules change); "Who has not read yet" with "Send a reminder in
   chat" (prepared message the lead can edit before sending).
6. [x] Plain wording in the app language (English, Hindi, Marathi, Telugu,
   like home) instead of UID, token, server, width and mode names; split the
   650-line group screen into list/home/manage parts with one shared confirm,
   report and error-with-retry widget; README group section for owners/leads.
7. [x] (Flutter suite 2405 pass, analysis clean apart from infos, rules tests pass, web and Android debug builds succeed. Browser run on the emulators, 2026-11-23, with a lead and a member account: create group, invite, join by link, plan by name, member sees own chapters and marks them read, counts update, reminder sent from the progress page and shown in chat with names, member sees no lead buttons. Fixed during the run: empty My week card on opening and on coming back to the group; reminder dialog error after sending. Not covered: Functions emulator, a real Android device, native-speaker review of hi/mr/te.) Tests: widget tests for every changed screen, emulator rules tests for
   lead invites, lead week advance and 8-letter codes, full regression, and a
   browser run with two accounts (port 8085 forwarded): create, invite, join,
   plan, read, mark done, progress, chat reminder.

# What we're NOT doing

- No push notifications or server jobs: reminders to the group are a chat
  message; personal device reminders stay as they are.
- No server functions or billing; no rate limiting on invite codes beyond
  8 letters (about 850 billion combinations), 24-hour expiry and revoke.
- Leads still cannot remove members, change roles, moderate, edit settings,
  archive or transfer ownership; those stay with the admin under Manage group.
- No redesign of home, reading, Naam Jaap, sign-in or Live Darshan screens.
- Other app languages fall back to English on group screens; Hindi, Marathi
  and Telugu wording still needs a native-speaker review.
- No feature removed; moderation, archive, restore and ownership transfer stay.
- No deploy, commit or push.
- Owner-only migration steps stay in docs/LAUNCH_CHECKLIST.md (Firebase
  project, rules deploy, signing, Play Console). Not possible here: iOS (needs a
  Mac), push notifications from a server and SMS (need the paid plan), and
  per-account separation of local bookmarks on shared phones (owner decision
  DEC-05). The FastAPI backend stays as an option; nothing is deleted.

# How we'll know it works

- In the browser, an admin creates a group, taps Invite, and a second account
  joins with the 8-letter code; both see each other's names, not IDs.
- A lead plans the week, the member taps "I have read it" on group home (three
  taps from the home screen: My groups, the group, the button), and the lead
  sees "1 of 2 have read" and can send a chat reminder to the other.
- Flutter tests, emulator rules tests and analysis pass with no new warnings;
  feed tests prove the direct Android path parses real sai.org.in pages.
