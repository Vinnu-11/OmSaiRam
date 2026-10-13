# Om Sai Ram — Backend

FastAPI + SQLAlchemy + PostgreSQL API for identity, reading groups, chapter assignments, progress, chat/highlights, reminder settings, festival metadata and Live Darshan stream discovery.

## Documentation

- [Requirements specification](../docs/REQUIREMENTS.md)
- [Project overview](../README.md)
- [User guide](../docs/USER_GUIDE.md)
- [QA test plan and cases](../docs/QA_TEST_CASES.md)
- Interactive OpenAPI: `http://localhost:8000/docs`; schema: `http://localhost:8000/openapi.json`.

## Local setup

Python 3.10+ is required by the source. Install the pinned packages from [requirements.txt](requirements.txt) in an isolated environment.

### Compose development environment

Run `docker compose up -d --build` from the backend directory after configuring your container CLI. This uses [docker-compose.yml](docker-compose.yml): PostgreSQL 16 on port5432 and API on port8000, development credentials and hot reload.

**Important:** Compose sets its API environment directly. Copying [the environment example](.env.example) to a local environment file does not override those explicitly specified Compose service values automatically. Change/override the Compose configuration for a different deployment. Never expose this development configuration publicly.

### Run without containers

Create/activate a virtual environment, install [requirements.txt](requirements.txt), copy [the environment example](.env.example) to a local environment file and configure the database URL/JWT secret/CORS. Start PostgreSQL separately, then run `uvicorn app.main:app --reload` from this directory.

The health endpoint is `http://localhost:8000/health`. A device/emulator must use a reachable host address, not its own localhost.

## Configuration

[Settings](app/config.py) load environment variables and a local environment file. Do not commit real secrets.

| Variable | Default / purpose |
|---|---|
| `APP_NAME` | Om Sai Ram API |
| `DEBUG` | false; development may enable true |
| `API_VERSION` | v1; routes are prefixed `/api/v1` |
| `DATABASE_URL` | Local PostgreSQL connection; replace credentials/host for deployment |
| `JWT_SECRET_KEY` | Unsafe sentinel default; required secure override in production |
| `JWT_ALGORITHM` | HS256 |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 30 |
| `REFRESH_TOKEN_EXPIRE_DAYS` | 7 |
| `CORS_ORIGINS` | JSON array, default wildcard; production must restrict origins |
| `GOOGLE_CLIENT_ID` | Empty by default; setting it alone does not implement provider verification |

Startup refuses the exact default JWT-secret sentinel when DEBUG=false. That guard is not a general secret-strength validator; choose a strong random value yourself. Use TLS, deployment-specific secrets and private database connectivity.

## Database and chapter index

- [Models](app/models/models.py) define users, memberships/groups, chapters, assignments/progress, messages, highlights, phone OTPs, festivals and reminder schedules.
- Startup currently calls SQLAlchemy metadata creation; Alembic configuration/migrations also exist. Metadata creation does **not** migrate existing columns/constraints. Review migrations and backup before upgrading an existing database.
- When the chapters table is entirely empty, startup seeds 53 Marathi index rows from [chapter titles](app/data/chapter_titles.json). If any rows already exist, startup does not repair a partial index.
- Seeded chapter content is empty/version0: the reader text stays in the Flutter assets. Those rows supply real database IDs for assignments.
- Do not assume chapter database ID equals original chapter number or a bundled JSON ID.
- Group reading units are 16–17, 18–19, 43–44 and51–53 plus all remaining singleton numbers: **48 units**. Chapter50 remains separate even when a translation falls back to Marathi.
- Existing saved schedules are not migrated to merged units automatically.

## Endpoint reference

All entries below use `/api/v1` unless noted. Authorization is enforced by the API; UI visibility does not grant permission. **Lead** means admin or group_lead; **member** means a member of the referenced group.

| Method | Path | Access / behavior |
|---|---|---|
| GET | `/health` (no version prefix) | Public health status |
| POST | `/auth/register` | Public email/password registration; optional normalized phone |
| POST | `/auth/login` | Public email/password login; failure throttling |
| POST | `/auth/social` | Public schema; incomplete Google/Apple verification; not production-ready |
| POST | `/auth/phone/send-otp` | Public rate-limited test OTP creation; no real SMS sender |
| POST | `/auth/phone/verify-otp` | Public OTP login/new-account flow |
| POST | `/auth/refresh` | Valid refresh JWT; deleted user rejected |
| GET | `/auth/me` | Authenticated own profile |
| PATCH | `/auth/me` | Authenticated own profile update |
| DELETE | `/auth/me` | Own account anonymization; blocked while admin of any group |
| POST | `/auth/change-password` | Email account with correct current password |
| GET | `/groups` | Own memberships |
| POST | `/groups` | Authenticated group creation; creator becomes admin |
| POST | `/groups/join` | Authenticated invite-code join |
| GET | `/groups/{group_id}` | Member; group and membership detail |
| DELETE | `/groups/{group_id}` | Admin only |
| DELETE | `/groups/{group_id}/leave` | Member/lead; admin cannot leave |
| PATCH | `/groups/{group_id}/settings` | Admin only; schedule settings |
| PATCH | `/groups/{group_id}/members/role` | Admin only; cannot demote self as admin |
| POST | `/groups/{group_id}/members` | Lead; add registered user |
| DELETE | `/groups/{group_id}/members/{user_id}` | Admin/lead may remove ordinary members; only admin may remove a lead; self/admin removal blocked |
| GET | `/groups/{group_id}/search-users` | Lead; masked contact lookup, max20 results |
| POST | `/assignments` | Lead; manually assign real chapter ID/member/week |
| POST | `/assignments/auto-schedule` | Lead; create weekly unit schedule |
| POST | `/assignments/suggest` | Lead; preview from hints, no assignment writes |
| POST | `/assignments/advance-week/{group_id}` | Lead; advance current reading week |
| GET | `/assignments/group/{group_id}` | Member; optional week filter |
| GET | `/assignments/my` | Own assignments across groups |
| DELETE | `/assignments/{assignment_id}` | Lead in assignment's group |
| PATCH | `/progress/{assignment_id}` | Assignee only, even if caller is admin/lead |
| GET | `/progress/{assignment_id}` | Group member |
| GET | `/content/versions` | Public; language query and version/count |
| GET | `/content/chapters/{language}` | Public server chapter index/content |
| GET | `/content/chapters/{language}/{chapter_number}` | Public original-number lookup |
| GET | `/groups/{group_id}/messages` | Member; newest-first cursor pagination, limit1–100 |
| POST | `/groups/{group_id}/messages` | Member; trimmed message1–2000 characters |
| DELETE | `/groups/{group_id}/messages/{message_id}` | Author or lead in same group |
| GET | `/groups/{group_id}/highlights` | Member; optional chapter-ID filter |
| POST | `/groups/{group_id}/highlights` | Member; server chapter ID, highlighted text/comment |
| DELETE | `/groups/{group_id}/highlights/{highlight_id}` | Author or lead in same group |
| GET | `/groups/{group_id}/notification-schedule` | Member;404 when no schedule configured |
| PUT | `/groups/{group_id}/notification-schedule` | Lead; persist local-device reminder configuration |
| GET | `/festivals` | Public cached festival data; see OpenAPI for current response |
| POST | `/festivals/refresh` | Any authenticated user currently; forced upstream refresh is not restricted to group admins |
| GET | `/live-darshan/stream-url` | Public; fetch fresh upstream HLS URL or502 |

Use OpenAPI for exact fields/status codes. Registration/login/token responses are sensitive; redact them in test reports.

## Assignment behavior

### Manual

Required: group ID, target member user ID and real server chapter ID. Week defaults to1. Interior numbers of a combined range normalize to its first chapter.

Duplicates are rejected for the same member/group/week across the entire range. A reading can repeat in a later week. If no date is supplied, the API chooses Monday using selected week minus group current week relative to the current Monday; an explicit date is preserved.

Responses include chapter number, `chapter_label` and `chapter_end_number`. One ReadingProgress row starts at `not_started`.

### Automatic and suggestions

- Modes: independent, rotating_window, dense_window, synchronized.
- Weeks ahead:1–12. Assignment calculations use **unit positions**, not raw chapter-number offsets.
- Cycle wraps after final unit51–53 to1; truncate/manual report unsatisfied slots.
- Extend-last/round-robin correctness and preview-versus-confirmation for later weeks/custom steps remain release test targets; do not certify from option labels alone.
- Suggested slots include original `chapter_numbers` and full `chapter_labels`.
- Same-member/week existing units are skipped; query-based duplicate prevention is not a concurrency uniqueness guarantee.

## External services and limitations

- Email/password auth is implemented. Social backend verification is not: Google currently returns501; Apple returns a controlled email-extraction error. A configured client ID alone does not change this.
- Phone OTP is hashed in the database but logged in plaintext for development delivery. Integrate SMS and remove sensitive production logging before shipping phone auth.
- Auth throttling is in-memory/process-local, not distributed. JWTs are stateless; password change/logout do not imply global revocation of every existing token.
- Reminder settings live in the database; delivery is scheduled locally by the client, not server push.
- Chat has no WebSocket delivery contract.
- Festival refresh is an APScheduler startup job plus daily job; review multi-worker duplicate job behavior.
- Live Darshan depends on HTML extraction from the official upstream and a changing HLS URL. Upstream failures return502; the API is not a video transcoding service.
- Cascade/cleanup and concurrent-operation guarantees require PostgreSQL tests, not only SQLite unit tests.

## Tests and release checks

Run `pytest -q` from this directory in the configured Python environment. Tests include [auth](tests/test_auth.py), [groups/progress](tests/test_groups_and_progress.py) and [combined/manual scheduling](tests/test_combined_chapters.py). The existing fast suites use SQLite; use a disposable PostgreSQL environment for concurrency, migrations, FK cleanup and deployment QA.

See [QA cases](../docs/QA_TEST_CASES.md) for the permissions matrix, test fixtures, pass/fail criteria and missing automation targets. A green unit suite is not production certification for SMS, OAuth, notifications or external streams.