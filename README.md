<!-- Om Sai Ram -->

# Om Sai Ram 🙏

A Flutter app for individual and group readings of the **Shri Sai Satcharita**, backed by FastAPI and PostgreSQL. Android and web targets are checked in; other Flutter platforms need separate setup and certification.

## Documentation

- [Requirements specification](docs/REQUIREMENTS.md) — scope, roles, business rules, functional/nonfunctional requirements, acceptance criteria and open decisions.
- [User guide](docs/USER_GUIDE.md) — manual/automatic readings, combined chapters, roles and everyday use.
- [QA test plan and cases](docs/QA_TEST_CASES.md) — prioritized functional, API, security, accessibility, offline and release tests; execution/defect templates.
- [Flutter setup and architecture](om_sai_ram/README.md).
- [Backend setup, configuration and API reference](backend/README.md).

Documentation reviewed against source on **2026-10-13**. Test cases are a specification, not a claim that all features/platforms have passed QA.

## About

This app allows devotees to come together in groups and read the Sai Baba Satcharita in an organized manner — either as a **chapter-wise** or **weekly Parayana (Saptah)**. Different members of the group are assigned different chapters, and the app tracks and displays the reading status of each participant.

## Features

- **Authentication** — Email/password signup, login, JWT refresh, profile/password updates and account anonymization. Phone OTP is a development flow; production SMS and Google/Apple provider verification are not implemented.
- **Group Management** — Invite codes, membership, admins/leads, user lookup and role-restricted management.
- **Manual Assignment** — Choose a member, reading week and one/multiple chapters from the group Schedule tab.
- **Automatic Scheduling** — Independent, rotating-window, dense-window and synchronized modes, plus pattern suggestions and week navigation. Preview/confirmation and remainder redistribution need release QA.
- **Combined Readings** — 16–17, 18–19, 43–44 and 51–53 are assigned once each. The 53 original chapters become 48 group reading units; Marathi originals are assembled within group assignments.
- **Reading Status** — Each member updates their own server-backed reading progress; other clients see changes after supported refresh, not guaranteed instant real-time delivery.
- **Offline Reader** — Bundled scripture, bookmarks, font/dark-mode settings, resume/local history and per-language caching.
- **Languages** — 18 bundled books, 17 selectable languages; Urdu selection disabled and some OCR-based languages labeled beta.
- **Audio and Live Darshan** — Aarti/chapter recordings, native chapter download cache, web streaming and an externally sourced live stream.
- **Community and Reminders** — Group chat/highlight API/display and native local reading/daily-verse reminders; not server push.
- **Information** — Dashboard, FAQ, daily programme and cached festival events.

### Current limitations

The presence of a social-login button, Saptah mode label or platform plugin does not establish a fully implemented integration. Real SMS delivery, provider-token verification, non-Android/web platform certification, timezone/DST reminder accuracy, concurrent-write safety and linguistic content review remain explicit test targets. See [QA rules and risks](docs/QA_TEST_CASES.md#verified-rules-and-limitations).

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **App** | Flutter (Dart) — checked-in Android and web targets |
| **Backend API** | Python FastAPI |
| **Database** | PostgreSQL |
| **Auth** | JWT (access + refresh tokens), bcrypt password hashing |
| **State Management** | Riverpod |
| **Navigation** | GoRouter (declarative) |
| **Containerization** | Docker + Docker Compose |

## Project Structure

```
OmSaiRam/
├── om_sai_ram/                 # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── app.dart            # Root widget, theme, routing
│   │   ├── core/               # Constants, theme, services, utils
│   │   ├── features/           # Feature modules (auth, groups, reader, etc.)
│   │   └── shared/             # Reusable widgets
│   └── assets/                 # Bundled content, images, i18n
├── backend/                    # Python FastAPI backend
│   ├── app/
│   │   ├── main.py             # FastAPI app entry
│   │   ├── config.py           # Settings from environment
│   │   ├── database.py         # SQLAlchemy setup
│   │   ├── models/             # Database models
│   │   ├── schemas/            # Pydantic request/response schemas
│   │   ├── routers/            # API route handlers
│   │   └── middleware/         # Auth middleware (JWT)
│   ├── migrations/             # Alembic DB migrations
│   ├── tests/                  # pytest test suite
│   ├── Dockerfile
│   └── docker-compose.yml      # Local dev (API + PostgreSQL)
├── docs/                       # User guide and QA test-case catalogue
└── README.md
```

## Getting Started

### Prerequisites

- **Compatible current Flutter stable SDK / Dart 3**: [Install Flutter](https://docs.flutter.dev/get-started/install); check dependency requirements in [pubspec.yaml](om_sai_ram/pubspec.yaml).
- **Python** (3.10+): [Install Python](https://www.python.org/downloads/)
- **Docker & Docker Compose**: [Install Docker](https://docs.docker.com/get-started/)

### Backend Setup

```bash
# 1. Navigate to the backend directory
cd backend

# 2. For non-container runs, copy environment file and configure
cp .env.example .env

# 3. Start the backend (API + PostgreSQL) with Docker
docker compose up -d --build

# 4. The API is now running at http://localhost:8000
#    Swagger docs at http://localhost:8000/docs
```

**Without Docker:**
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Linux/Mac
pip install -r requirements.txt
# Start PostgreSQL separately, then:
uvicorn app.main:app --reload
```

Compose explicitly supplies development database/JWT/DEBUG values; copying the environment example does not override those service values automatically. Do not expose that setup publicly. See [backend configuration](backend/README.md#configuration) for secure environment settings and startup/schema behavior.

### Flutter App Setup

```bash
# 1. Navigate to the Flutter project
cd om_sai_ram

# 2. Install dependencies (Android/web files already exist)
flutter pub get

# 3. Run on connected device, emulator or supported browser target
flutter run
```

Set `API_BASE_URL` using Flutter's `--dart-define` for a host reachable from the target. The default is localhost:8000, which is not the development machine when used on an Android emulator/phone. Production web requires HTTPS, compatible CORS and SPA deep-link hosting. See [Flutter setup](om_sai_ram/README.md#run-locally).

### Running Tests

```bash
# Backend tests
cd backend
pytest

# Flutter tests
cd om_sai_ram
flutter test
```

The [QA catalogue](docs/QA_TEST_CASES.md) covers manual/E2E/API/platform scenarios beyond the existing unit/widget suites. It includes fixtures, priorities, permissions, acceptance criteria, traceability and execution/defect reporting. Tests must be executed per target platform and release build; catalogue entries start **Not Run**.

Existing automated coverage includes auth/groups/progress, combined-unit scheduling, manual assignment dates/duplicates, real server chapter-ID selection, partial saves and keyboard layout. SQLite suites do not replace PostgreSQL concurrency/cascade checks, real-device reminders, media or content-language review.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/register` | Register new user |
| POST | `/api/v1/auth/login` | Login with email/password |
| POST | `/api/v1/auth/social` | Incomplete Google/Apple provider-verification placeholder |
| POST | `/api/v1/auth/refresh` | Refresh access token |
| GET | `/api/v1/auth/me` | Get current user profile |
| GET | `/api/v1/groups` | List user's groups |
| POST | `/api/v1/groups` | Create a new group |
| POST | `/api/v1/groups/join` | Join group via invite code |
| GET | `/api/v1/groups/{id}` | Get group details + members |
| POST | `/api/v1/assignments` | Assign chapter to member |
| GET | `/api/v1/assignments/my` | Get my assignments |
| PATCH | `/api/v1/progress/{id}` | Update reading progress |
| GET | `/api/v1/content/chapters/{lang}` | Get all chapters |
| GET | `/api/v1/content/versions` | Check content version |

Additional routes cover phone OTP, profile/password/deletion, group role/member management, auto-schedules/suggestions/week advancement, group chat/highlights, reminder settings, festivals and live-stream discovery. See the [complete backend endpoint reference](backend/README.md#endpoint-reference) or `http://localhost:8000/docs`. The social route is a placeholder, not a working provider-verification service.

## Design Philosophy

- **Simple & Minimalist** — Warm saffron/white palette, clean layouts
- **Easy Navigation** — Bottom nav bar with 4 tabs (Home, Groups, Reader, Profile)
- **Readable** — Serif font for scripture, generous spacing in the reader
- **Offline-First Reader** — Scripture bundled in app; group/auth writes need connectivity and are not automatically queued offline
- **Server-enforced Roles** — Admin-only settings/roles/deletion; leads can assign/manage ordinary members; only the assignee updates progress
- **Transparent Capability Claims** — External integrations, beta OCR languages and platform limitations documented and tested explicitly

---

> *"Before we begin any task, we must first remember Sai Baba and seek His blessings."*

