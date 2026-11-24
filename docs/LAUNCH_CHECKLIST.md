# Launch checklist — Om Sai Sannidhi (Android first)

The app code is ready for a Firebase release. The steps below need the owner's
accounts, keys or decisions and cannot be done from this repository. Work top to
bottom; each step says what to give the build.

Nothing here has been deployed. Cost notes follow
[FIREBASE_ANDROID_LAUNCH.md](FIREBASE_ANDROID_LAUNCH.md).

## 1. Decide the Android application ID

Pick a permanent ID such as `org.yourname.omsaisannidhi`, then replace
`com.example.om_sai_ram` in
[om_sai_ram/android/app/build.gradle.kts](../om_sai_ram/android/app/build.gradle.kts)
(`applicationId` only; `namespace` can stay). Google Play rejects `com.example`
IDs, and the ID can never change after the first upload.

## 2. Create the Firebase project

1. In the Firebase console create a project (Spark plan is enough for email,
   Google and Apple sign-in).
2. Create Cloud Firestore in **production mode**. Recommended location:
   `asia-south1` (Mumbai). The location cannot be changed later.
3. Add an **Android app** with the application ID from step 1.
4. Authentication > Sign-in method: enable **Email/Password**. Enable the others
   as you complete their steps below.
5. Authentication > Settings > User account linking: keep
   **Link accounts that use the same email**. The app never merges accounts
   itself. With this setting Firebase refuses an Apple sign-in whose email
   already belongs to another account until the user links it from Sign-in
   methods, and treats a Google sign-in as proof of email ownership: it opens
   the existing account with that email or refuses, but never creates a second
   account for it.

## 3. Give the build its project settings

Copy [firebase.production.example.json](../om_sai_ram/firebase.production.example.json)
to `om_sai_ram/firebase.production.json` and fill it from Firebase console >
Project settings > Your apps. These values are public identifiers, not secrets.

| Key | Value |
|---|---|
| `FIREBASE_PROJECT_ID` | Project ID |
| `FIREBASE_API_KEY` | Android app API key |
| `FIREBASE_APP_ID` | Android app ID (`1:…:android:…`) |
| `FIREBASE_MESSAGING_SENDER_ID` | Project number |
| `FIREBASE_AUTH_DOMAIN` | Leave empty for `<project>.firebaseapp.com` |
| `GOOGLE_SERVER_CLIENT_ID` | Web client ID, for Google sign-in (step 6) |
| `FIREBASE_FEEDS_BASE_URL` | Leave empty unless Functions are deployed (step 9) |

A web release needs its own file using the **Web app** values.

## 4. Deploy the security rules

```bash
cd firebase
npx firebase login
npx firebase deploy --only firestore:rules,firestore:indexes --project <project-id>
```

Run `npm test` in `firebase/` first; it must report every test passing. Never
switch the database to test mode.

## 5. Create the upload key and sign the release

```bash
keytool -genkey -v -keystore ~/om-sai-sannidhi-upload.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Create `om_sai_ram/android/key.properties` (already ignored by git):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=/home/<you>/om-sai-sannidhi-upload.jks
```

Keep the keystore and passwords backed up outside the repository. Then build:

```bash
cd om_sai_ram
flutter build appbundle --release --dart-define-from-file=firebase.production.json
```

Without `key.properties` the build falls back to the debug key and Google Play
will reject it.

## 6. Google sign-in

1. Enable **Google** in Authentication > Sign-in method.
2. Project settings > Your apps > Android: add the **SHA-1 and SHA-256** of the
   upload key (`keytool -list -v -keystore … -alias upload`). After the first
   Play upload, also add the **Play App Signing** key fingerprints from Play
   Console > Setup > App integrity.
3. Put the **Web client ID** (Authentication > Sign-in method > Google > Web SDK
   configuration) in `GOOGLE_SERVER_CLIENT_ID`.

## 7. Phone sign-in (paid)

SMS requires the **Blaze** plan and is charged per message. Enable **Phone**,
make sure the SHA-256 fingerprints from step 6 are registered, and set an SMS
region policy (India only is the cheapest safe default) plus a budget alert. To
launch without it, leave Phone disabled: the button then shows "This sign-in
method is not enabled for this project."

## 8. Apple sign-in

Needs a paid Apple Developer account: create a Services ID and key, then enable
**Apple** in Authentication with them. It is only required by Apple's own store;
for an Android-only launch it can stay disabled.

## 9. Live darshan and festival feeds (Functions optional, paid)

With `FIREBASE_FEEDS_BASE_URL` empty, the **Android** app reads both pages
directly from sai.org.in, with the same checks as the server (only sai.org.in
hosts, HTTPS, 1 MiB limit, a single agreed stream URL). No Blaze plan is needed
for that. The **web** app cannot read the temple site directly (the site sends
no CORS headers), so on the web both screens show "This feed is not available
in this release." until the Cloud Functions in `firebase/functions` are
deployed (Blaze plan) and `FIREBASE_FEEDS_BASE_URL` points at them.

Note (2026-11-22): the temple's festivals page currently lists no dated
festivals, so the festivals screen shows "Feed unavailable" with a retry
button. This happens with or without the Functions.

## 10. Privacy policy and account deletion pages

Google Play requires both URLs.

1. Edit the highlighted placeholders (developer name, contact email, date) in
   [privacy.html](../om_sai_ram/web/privacy.html) and
   [delete-account.html](../om_sai_ram/web/delete-account.html). Have the text
   reviewed; it is a truthful draft of what the app stores, not legal advice.
2. Publish them with the web build on Firebase Hosting (free):

```bash
cd om_sai_ram
flutter build web --release --dart-define-from-file=firebase.production.web.json
cd ../firebase && npx firebase deploy --only hosting --project <project-id>
```

The pages are then at `https://<project-id>.web.app/privacy.html` and
`/delete-account.html`.

## 11. Test on a real phone before uploading

Emulator and unit tests pass, but none of this has run against a real Firebase
project or device. Install the release build and check at least: sign up, log
out and in, password reset email arrives, create a group, invite and join from a
second account, assign and complete a chapter, chat, reminders fire at the set
time, transfer ownership, delete the second account, offline reading and audio.

## 12. Google Play

1. Create the app in Play Console with the name **Om Sai Sannidhi**.
2. Store listing: icon, screenshots, short and full description.
3. App content: privacy policy URL, **Data safety** form (email/phone, name,
   messages, app activity; no ads; data encrypted in transit; deletion URL from
   step 10), content rating and target audience.
4. Confirm you may distribute the Satcharita text and audio you bundle or link.
5. Upload the `.aab` to **Internal testing** first. New personal developer
   accounts must also complete Google's closed-testing requirement before
   production.

## Still open after launch

- The Firebase screens use plain development wording and layout; the UI pass is
  planned separately.
- iOS is not configured.
- The FastAPI backend remains selectable with `--dart-define=BACKEND_MODE=fastapi`
  and is the default on desktop. Retire it only after the release is accepted.
