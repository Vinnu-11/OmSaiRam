<!-- Om Sai Ram -->

# Om Sai Ram 🙏

A cross-platform mobile app for organizing group readings of the **Shri Sai Satcharita**.

## About

This app allows devotees to come together in groups and read the Sai Baba Satcharita in an organized manner — either as a **chapter-wise** or **weekly Parayana (Saptah)**. Different members of the group are assigned different chapters, and the app tracks and displays the reading status of each participant.

## Features

- **Authentication** — Email/password signup & login + Google/Apple social sign-in
- **Group Management** — Create and manage groups of devotees with invite codes
- **Member Assignment** — Assign specific chapters to different members within a group
- **Chapter & Weekly Parayana** — Support for both chapter-by-chapter and week-based (Saptah) reading modes
- **Reading Status** — Track and display the reading progress of each member in real time
- **Satcharita Reader** — Clean, distraction-free reader for all 53 chapters
- **Overview Dashboard** — Quick stats, groups summary, and inspirational quotes
- **FAQ** — Comprehensive help section for new users
- **Multi-language Ready** — Architecture supports adding Hindi, Marathi, Telugu, and more

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Mobile App** | Flutter (Dart) — Android, iOS, iPad, Android tablet |
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
└── README.md
```

## Getting Started

### Prerequisites

- **Flutter SDK** (3.0+): [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Python** (3.10+): [Install Python](https://www.python.org/downloads/)
- **Docker & Docker Compose**: [Install Docker](https://docs.docker.com/get-started/)

### Backend Setup

```bash
# 1. Navigate to the backend directory
cd backend

# 2. Copy environment file and configure
cp .env.example .env

# 3. Start the backend (API + PostgreSQL) with Docker
docker-compose up -d

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

### Flutter App Setup

```bash
# 1. Navigate to the Flutter project
cd om_sai_ram

# 2. Generate platform files (first time only)
flutter create .

# 3. Install dependencies
flutter pub get

# 4. Run on connected device or emulator
flutter run
```

### Running Tests

```bash
# Backend tests
cd backend
pytest

# Flutter tests
cd om_sai_ram
flutter test
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/register` | Register new user |
| POST | `/api/v1/auth/login` | Login with email/password |
| POST | `/api/v1/auth/social` | Social login (Google/Apple) |
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

## Design Philosophy

- **Simple & Minimalist** — Warm saffron/white palette, clean layouts
- **Easy Navigation** — Bottom nav bar with 4 tabs (Home, Groups, Reader, Profile)
- **Readable** — Serif font for scripture, generous spacing in the reader
- **Offline-First** — Satcharita content bundled in app, server updates in background

---

> *"Before we begin any task, we must first remember Sai Baba and seek His blessings."*

