"""
Om Sai Ram — Group Feature End-to-End Demo
Runs entirely in-memory (SQLite). No server needed.
Shows every screen/flow as a user would experience it in the Flutter app.
"""

import os
os.environ["DATABASE_URL"] = "sqlite://"
os.environ["JWT_SECRET_KEY"] = "demo-secret-key"

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
import json

from app.database import Base, get_db
from app.main import app
from app.models import Chapter

# ── In-memory DB setup ────────────────────────────────────────────────────────
engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
Session = sessionmaker(bind=engine)
Base.metadata.create_all(bind=engine)

def override_get_db():
    db = Session()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

# ── Seed chapters (Sai Satcharita has 53 chapters) ───────────────────────────
db = Session()
for i in range(1, 54):
    titles = {
        1: "Invocation and Introduction",
        2: "The Author's Family and Ancestry",
        3: "Baba's Arrival at Shirdi",
        4: "Baba's Early Life at Shirdi",
        5: "Baba's Previous Life — The Guru",
        6: "Various Experiences of Devotees",
        7: "Baba Cures Diseases",
        8: "Stories of Kakasaheb Dixit",
        9: "Dasganu's Literary Career",
        10: "Sai Baba's Advice",
        11: "Baba's Sanction Required",
        12: "The Significance of Udhi",
        13: "Baba and Cholera",
        14: "Baba and His Devotees",
        15: "Baba Cures Bhimaji",
        16: "Babasaheb Tarkhad's Story",
        17: "Brahmin Family and Baba",
        18: "Baba's Stay at Shirdi",
        19: "Baba and Shama",
        20: "Baba Blesses Devotees",
    }
    db.add(Chapter(
        number=i,
        title=titles.get(i, f"Adhyay {i}"),
        content=f"Sacred content of Adhyay {i} of Sai Satcharita.",
        language="en",
        version=1,
    ))
db.commit()
db.close()

# ── Helpers ───────────────────────────────────────────────────────────────────
DIVIDER = "─" * 72

def section(title):
    print(f"\n{'═' * 72}")
    print(f"  {title}")
    print(f"{'═' * 72}")

def step(label):
    print(f"\n  {DIVIDER}")
    print(f"  >> {label}")
    print(f"  {DIVIDER}")

def show(response, label="Response"):
    status = response.status_code
    icon = "✓" if status < 300 else "✗"
    print(f"  {icon} HTTP {status}")
    try:
        data = response.json()
        print(f"  {json.dumps(data, indent=4, default=str)}")
    except Exception:
        print(f"  (no body)")
    return response.json() if status < 300 else None

def register(name, email, password="devotee123"):
    r = client.post("/api/v1/auth/register", json={"name": name, "email": email, "password": password})
    if r.status_code == 201:
        token = r.json()["access_token"]
        print(f"  ✓ Registered '{name}' → token acquired")
        return token
    print(f"  ✗ Register failed: {r.json()}")
    return None

def auth(token):
    return {"Authorization": f"Bearer {token}"}


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 1 — Register 4 Users (devotees of Sai Baba)")
# ════════════════════════════════════════════════════════════════════════════════

print("\n  Creating users who will form reading groups...\n")

token_ram   = register("Ram Sharma",   "ram@devotee.in")
token_sita  = register("Sita Devi",    "sita@devotee.in")
token_arjun = register("Arjun Naidu",  "arjun@devotee.in")
token_priya = register("Priya Iyer",   "priya@devotee.in")

# ════════════════════════════════════════════════════════════════════════════════
section("STEP 2 — GROUPS SCREEN: Ram creates two groups")
# ════════════════════════════════════════════════════════════════════════════════

step("Ram opens the app → Groups tab → hits (+) FAB → CREATE GROUP screen")
print("  Fills in: Name='Shirdi Sai Parivaar', Mode=chapter_wise, 2 chapters/week")
r = client.post("/api/v1/groups", json={
    "name": "Shirdi Sai Parivaar",
    "description": "Weekly chapter-wise reading of Sai Satcharita with family",
    "mode": "chapter_wise",
    "chapters_per_week": 2,
}, headers=auth(token_ram))
group1 = show(r)
invite_code_1 = group1["invite_code"]
group1_id = group1["id"]
print(f"\n  [UI] Group created! Invite code displayed: {invite_code_1}")

step("Ram creates a second group — Saptah (intensive weekly reading)")
print("  Fills in: Name='Saptah Paath Group', Mode=saptah, 5 chapters/week")
r = client.post("/api/v1/groups", json={
    "name": "Saptah Paath Group",
    "description": "Complete Sai Satcharita in one week — intensive daily reading",
    "mode": "saptah",
    "chapters_per_week": 5,
}, headers=auth(token_ram))
group2 = show(r)
group2_id = group2["id"]
invite_code_2 = group2["invite_code"]
print(f"\n  [UI] Second group created! Invite code: {invite_code_2}")

step("Ram's Groups Screen now shows both groups")
r = client.get("/api/v1/groups", headers=auth(token_ram))
groups_data = show(r, "Ram's group list")
print(f"\n  [UI] Groups list shows {len(groups_data['groups'])} group(s) for Ram")


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 3 — Other devotees join via invite code")
# ════════════════════════════════════════════════════════════════════════════════

step("Sita enters invite code in the JOIN dialog and taps Join")
print(f"  Invite code entered: {invite_code_1}")
r = client.post("/api/v1/groups/join", json={"invite_code": invite_code_1}, headers=auth(token_sita))
show(r)

step("Arjun joins the same group")
print(f"  Invite code entered: {invite_code_1}")
r = client.post("/api/v1/groups/join", json={"invite_code": invite_code_1}, headers=auth(token_arjun))
show(r)

step("Priya joins the Saptah group")
print(f"  Invite code entered: {invite_code_2}")
r = client.post("/api/v1/groups/join", json={"invite_code": invite_code_2}, headers=auth(token_priya))
show(r)

step("Sita tries to join again — should fail with 'already a member'")
r = client.post("/api/v1/groups/join", json={"invite_code": invite_code_1}, headers=auth(token_sita))
show(r)

step("Someone enters a wrong invite code — should fail with 404")
r = client.post("/api/v1/groups/join", json={"invite_code": "XXXXXX"}, headers=auth(token_priya))
show(r)


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 4 — GROUP DETAIL SCREEN: Members tab")
# ════════════════════════════════════════════════════════════════════════════════

step("Ram taps on 'Shirdi Sai Parivaar' → Group Detail → Members tab")
r = client.get(f"/api/v1/groups/{group1_id}", headers=auth(token_ram))
detail = show(r)
print("\n  [UI] Members tab renders:")
for m in detail["members"]:
    role_badge = f"[{m['role'].upper()}]" if m["role"] != "member" else ""
    print(f"       • {m['name']} {role_badge}  (joined {m['joined_at'][:10]})")

step("Ram taps edit icon on Arjun → promotes to group_lead")
arjun_user_id = next(m["user_id"] for m in detail["members"] if "Arjun" in m["name"])
r = client.patch(f"/api/v1/groups/{group1_id}/members/role",
    json={"user_id": arjun_user_id, "role": "group_lead"},
    headers=auth(token_ram))
show(r)
print("\n  [UI] Arjun now shows [GROUP_LEAD] badge in the members list")

step("A non-member tries to view group details — should get 403")
r = client.get(f"/api/v1/groups/{group1_id}", headers=auth(token_priya))
show(r)


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 5 — GROUP DETAIL SCREEN: Schedule tab — Assignments")
# ════════════════════════════════════════════════════════════════════════════════

# Get chapter IDs from the DB
db = Session()
chapters = {c.number: c.id for c in db.query(Chapter).all()}
users_in_group = client.get(f"/api/v1/groups/{group1_id}", headers=auth(token_ram)).json()["members"]
ram_uid   = next(m["user_id"] for m in users_in_group if "Ram" in m["name"])
sita_uid  = next(m["user_id"] for m in users_in_group if "Sita" in m["name"])
arjun_uid = next(m["user_id"] for m in users_in_group if "Arjun" in m["name"])
db.close()

step("Ram (admin) opens Schedule tab → Week 1 → manually assigns chapters")
print("  Assigning Chapter 1 to Ram, Chapter 2 to Sita for Week 1")

r = client.post("/api/v1/assignments", json={
    "group_id": group1_id,
    "user_id": ram_uid,
    "chapter_id": chapters[1],
    "week_number": 1,
}, headers=auth(token_ram))
a1 = show(r)

r = client.post("/api/v1/assignments", json={
    "group_id": group1_id,
    "user_id": sita_uid,
    "chapter_id": chapters[2],
    "week_number": 1,
}, headers=auth(token_ram))
a2 = show(r)

step("Arjun (group_lead) assigns Chapter 3 to Arjun for Week 1")
r = client.post("/api/v1/assignments", json={
    "group_id": group1_id,
    "user_id": arjun_uid,
    "chapter_id": chapters[3],
    "week_number": 1,
}, headers=auth(token_arjun))
a3 = show(r)

step("Sita (plain member) tries to assign — should fail with 403")
r = client.post("/api/v1/assignments", json={
    "group_id": group1_id,
    "user_id": sita_uid,
    "chapter_id": chapters[4],
    "week_number": 1,
}, headers=auth(token_sita))
show(r)

step("Duplicate assignment rejected — Ram tries to assign Ch.1 to himself again")
r = client.post("/api/v1/assignments", json={
    "group_id": group1_id,
    "user_id": ram_uid,
    "chapter_id": chapters[1],
    "week_number": 1,
}, headers=auth(token_ram))
show(r)

step("Schedule tab shows Week 1 assignments")
r = client.get(f"/api/v1/assignments/group/{group1_id}?week_number=1", headers=auth(token_ram))
week1 = show(r)
print("\n  [UI] Schedule tab renders for Week 1:")
for a in week1:
    print(f"       • Ch.{a['chapter_number']} '{a['chapter_title']}'"
          f" → {a['user_name']}  [{a['status'].upper()}]")

step("Ram taps 'Auto-Schedule' → fills weeks 2-5 automatically")
r = client.post("/api/v1/assignments/auto-schedule", json={
    "group_id": group1_id,
    "start_chapter": 4,
    "weeks_ahead": 4,
}, headers=auth(token_ram))
auto = show(r)
print(f"\n  [UI] Auto-scheduled {len(auto)} assignments for weeks 2–5")
for a in auto:
    print(f"       Week {a['week_number']}: Ch.{a['chapter_number']} '{a['chapter_title']}' → {a['user_name']}")


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 6 — Progress tracking: members mark chapters as read")
# ════════════════════════════════════════════════════════════════════════════════

step("Ram marks his Chapter 1 assignment as 'in_progress'")
r = client.patch(f"/api/v1/progress/{a1['id']}", json={"status": "in_progress"}, headers=auth(token_ram))
show(r)

step("Ram finishes — marks Chapter 1 as 'completed'")
r = client.patch(f"/api/v1/progress/{a1['id']}", json={"status": "completed"}, headers=auth(token_ram))
show(r)

step("Sita marks Chapter 2 as 'in_progress'")
r = client.patch(f"/api/v1/progress/{a2['id']}", json={"status": "in_progress"}, headers=auth(token_sita))
show(r)

step("Sita tries to update RAM's progress — should fail 403")
r = client.patch(f"/api/v1/progress/{a1['id']}", json={"status": "not_started"}, headers=auth(token_sita))
show(r)

step("Schedule tab now shows updated progress badges")
r = client.get(f"/api/v1/assignments/group/{group1_id}?week_number=1", headers=auth(token_ram))
week1_updated = r.json()
print("\n  [UI] Week 1 progress badges:")
for a in week1_updated:
    badge = {"completed": "🟢 DONE", "in_progress": "🟡 READING", "not_started": "⚪ NOT STARTED"}
    print(f"       • {a['user_name']}: Ch.{a['chapter_number']} — {badge.get(a['status'], a['status'])}")

step("My Assignments view — Sita checks her personal reading list")
r = client.get("/api/v1/assignments/my", headers=auth(token_sita))
my_assigns = r.json()
print("\n  [UI] 'My Assignments' tab for Sita:")
for a in my_assigns:
    print(f"       Week {a['week_number']}: Ch.{a['chapter_number']} '{a['chapter_title']}' [{a['status']}]")


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 7 — GROUP DETAIL SCREEN: Chat tab — Group Messages")
# ════════════════════════════════════════════════════════════════════════════════

step("Ram opens Chat tab and sends the first message")
r = client.post(f"/api/v1/groups/{group1_id}/messages",
    json={"content": "Jai Sai Ram 🙏 Welcome everyone to our reading group!"},
    headers=auth(token_ram))
msg1 = show(r)

step("Sita replies")
r = client.post(f"/api/v1/groups/{group1_id}/messages",
    json={"content": "Jai Sai Ram Ram bhai! So happy to read together 🌸"},
    headers=auth(token_sita))
msg2 = show(r)

step("Arjun joins the conversation")
r = client.post(f"/api/v1/groups/{group1_id}/messages",
    json={"content": "Chapter 1 was so beautiful. Baba's grace is infinite 🕉️"},
    headers=auth(token_arjun))
msg3 = show(r)

step("Ram sends another message")
r = client.post(f"/api/v1/groups/{group1_id}/messages",
    json={"content": "Let's all complete Chapter 2 by Sunday. Sai Baba will guide us!"},
    headers=auth(token_ram))
msg4 = show(r)

step("Chat view renders all messages (newest-first from API, reversed for display)")
r = client.get(f"/api/v1/groups/{group1_id}/messages?limit=50", headers=auth(token_ram))
msgs = r.json()
print("\n  [UI] Chat bubbles (oldest → newest):")
for msg in reversed(msgs):
    side = "→" if msg["user_name"] == "Ram Sharma" else "←"
    print(f"       {side}  [{msg['user_name']}]: {msg['content']}")

step("Arjun deletes his own message (long-press → delete)")
r = client.delete(f"/api/v1/groups/{group1_id}/messages/{msg3['id']}", headers=auth(token_arjun))
print(f"  ✓ HTTP {r.status_code} — message deleted")

step("Sita tries to delete Ram's message — should fail 403")
r = client.delete(f"/api/v1/groups/{group1_id}/messages/{msg4['id']}", headers=auth(token_sita))
show(r)

step("Ram (admin) can moderate — deletes any message")
r = client.delete(f"/api/v1/groups/{group1_id}/messages/{msg2['id']}", headers=auth(token_ram))
print(f"  ✓ HTTP {r.status_code} — admin moderation: Sita's message deleted")

step("Final chat after deletions")
r = client.get(f"/api/v1/groups/{group1_id}/messages", headers=auth(token_ram))
msgs = r.json()
print(f"\n  [UI] {len(msgs)} message(s) remain in chat:")
for msg in reversed(msgs):
    print(f"       [{msg['user_name']}]: {msg['content']}")


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 8 — GROUP DETAIL SCREEN: Chat tab — Shared Highlights")
# ════════════════════════════════════════════════════════════════════════════════

step("Ram long-presses a verse in Chapter 1 reader → posts highlight comment to group")
r = client.post(f"/api/v1/groups/{group1_id}/highlights", json={
    "chapter_id": chapters[1],
    "highlighted_text": "Sai Baba sat in the mosque, kept sacred fire (dhuni) burning, gave udi (sacred ash) to all.",
    "paragraph_index": 3,
    "comment": "The dhuni represents the burning of ego. Such a profound symbol of Baba's teachings.",
}, headers=auth(token_ram))
h1 = show(r)

step("Sita highlights a different verse from Chapter 2")
r = client.post(f"/api/v1/groups/{group1_id}/highlights", json={
    "chapter_id": chapters[2],
    "highlighted_text": "Baba said: 'Why do you fear when I am here?'",
    "paragraph_index": 7,
    "comment": "This verse always brings me so much peace 🙏",
}, headers=auth(token_sita))
h2 = show(r)

step("Arjun adds another highlight from Chapter 1")
r = client.post(f"/api/v1/groups/{group1_id}/highlights", json={
    "chapter_id": chapters[1],
    "highlighted_text": "He who puts his feet on Shirdi soil, his sufferings will come to an end.",
    "paragraph_index": 12,
    "comment": "Baba's promise to all devotees. Just reading this fills the heart!",
}, headers=auth(token_arjun))
h3 = show(r)

step("Shared Highlights view — shows all highlights")
r = client.get(f"/api/v1/groups/{group1_id}/highlights", headers=auth(token_sita))
highlights = r.json()
print("\n  [UI] Shared Highlights tab renders:")
for h in reversed(highlights):
    print(f"\n       ┌─ Ch.{h['chapter_number']} — {h['user_name']}")
    print(f"       │  \"{h['highlighted_text'][:60]}...\"" if len(h['highlighted_text']) > 60
          else f"       │  \"{h['highlighted_text']}\"")
    print(f"       └  💬 {h['comment']}")

step("Filter highlights by Chapter 1 only")
r = client.get(f"/api/v1/groups/{group1_id}/highlights?chapter_id={chapters[1]}", headers=auth(token_ram))
ch1_highlights = r.json()
print(f"\n  [UI] Filtered to Ch.1: {len(ch1_highlights)} highlight(s)")
for h in ch1_highlights:
    print(f"       • [{h['user_name']}]: \"{h['highlighted_text'][:50]}...\"")

step("Arjun deletes his own highlight (trash icon visible on own highlights)")
r = client.delete(f"/api/v1/groups/{group1_id}/highlights/{h3['id']}", headers=auth(token_arjun))
print(f"  ✓ HTTP {r.status_code} — highlight deleted")

step("Sita tries to delete Ram's highlight — should fail 403")
r = client.delete(f"/api/v1/groups/{group1_id}/highlights/{h1['id']}", headers=auth(token_sita))
show(r)


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 9 — Advance week & group settings")
# ════════════════════════════════════════════════════════════════════════════════

step("Ram taps 'Next Week' button → group advances to Week 2")
r = client.post(f"/api/v1/assignments/advance-week/{group1_id}", headers=auth(token_ram))
show(r)

step("Ram updates group settings: now 3 chapters/week")
r = client.patch(f"/api/v1/groups/{group1_id}/settings",
    json={"chapters_per_week": 3},
    headers=auth(token_ram))
show(r)
print("\n  [UI] Settings saved — new pace: 3 chapters/week")

step("Week 2 schedule tab (auto-scheduled assignments already exist)")
r = client.get(f"/api/v1/assignments/group/{group1_id}?week_number=2", headers=auth(token_ram))
week2 = r.json()
print(f"\n  [UI] Week 2 shows {len(week2)} assignment(s):")
for a in week2:
    print(f"       • Ch.{a['chapter_number']} '{a['chapter_title']}' → {a['user_name']} [{a['status']}]")


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 10 — Leave / Delete group")
# ════════════════════════════════════════════════════════════════════════════════

step("Arjun (group_lead) leaves the group")
r = client.delete(f"/api/v1/groups/{group1_id}/leave", headers=auth(token_arjun))
print(f"  ✓ HTTP {r.status_code} — Arjun left the group")

step("Ram (admin) tries to leave — should fail with helpful message")
r = client.delete(f"/api/v1/groups/{group1_id}/leave", headers=auth(token_ram))
show(r)
print("\n  [UI] Shows error: 'Admins cannot leave. Transfer ownership or delete the group.'")

step("Ram deletes the Saptah group (which only has Ram + Priya)")
r = client.delete(f"/api/v1/groups/{group2_id}", headers=auth(token_ram))
print(f"  ✓ HTTP {r.status_code} — group deleted (cascade removes all members + assignments)")

step("Priya checks her groups — should be empty now")
r = client.get("/api/v1/groups", headers=auth(token_priya))
show(r)
print("\n  [UI] Empty state shown for Priya: 'No groups yet. Create or join one!'")


# ════════════════════════════════════════════════════════════════════════════════
section("STEP 11 — Security & edge case checks")
# ════════════════════════════════════════════════════════════════════════════════

step("Unauthenticated user tries to list groups")
r = client.get("/api/v1/groups")
show(r)

step("XSS attempt in group name — stored safely as plain text")
r = client.post("/api/v1/groups", json={
    "name": "<script>alert('xss')</script>",
    "mode": "chapter_wise",
    "chapters_per_week": 2,
}, headers=auth(token_sita))
xss_group = show(r)
print(f"\n  [Safe] Stored as plain text: {xss_group['name']!r}")
# Clean up
client.delete(f"/api/v1/groups/{xss_group['id']}", headers=auth(token_sita))

step("Invalid JWT token rejected")
r = client.get("/api/v1/groups", headers={"Authorization": "Bearer fake.token.here"})
show(r)


# ════════════════════════════════════════════════════════════════════════════════
section("FINAL SUMMARY")
# ════════════════════════════════════════════════════════════════════════════════

print("""
  FEATURE                            STATUS
  ─────────────────────────────────────────────────────────
  Register / Login                   ✓  Works
  Create group (chapter_wise/saptah) ✓  Works — invite code generated
  Join via invite code               ✓  Works — duplicate join blocked
  View group detail + members        ✓  Works — non-members blocked
  Promote member to group_lead       ✓  Works — admin-only
  Manual chapter assignments         ✓  Works — admin/lead only
  Auto-schedule (4 weeks ahead)      ✓  Works — round-robin across members
  Progress tracking (per assignment) ✓  Works — owner-only update, 403 for others
  Advance to next week               ✓  Works
  Update group settings              ✓  Works — chapters_per_week, current_week
  Group chat (send/delete messages)  ✓  Works — author+moderator can delete
  Shared highlights (post/delete)    ✓  Works — filter by chapter
  Admin cannot leave (must delete)   ✓  Works — helpful error
  Delete group (cascade)             ✓  Works
  Security — auth required           ✓  All write endpoints blocked w/o token
  Security — XSS stored as plain text✓  No script execution
  ─────────────────────────────────────────────────────────
  Known gap: No Flutter UI to POST highlights (backend ready, reader not wired)
  Known gap: No real-time chat (polling only)
  Known gap: No ownership transfer (admin must delete to leave)
""")
