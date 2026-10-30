# ChitChat

An independent Flutter Android chat app: a shared **Community chat** and public **Spill the Chaya** groups that last one hour. Anonymous guests can chat immediately. The creator automatically enters their group.

The final, simplified scope excludes college onboarding, feeds, events, media and role administration. Nothing is imported from Hostel Connect. The folder retains its original `community_connect` name; the app and Dart package are ChitChat.

## Included

- Supabase anonymous sign-in, optional email/password registration/login, verification, reset links and persistent sessions.
- PostgreSQL messages, RLS-protected realtime updates, 50-message pagination and optimistic sending with stable IDs and retry.
- Server-controlled group expiry and automatic cascading deletion.
- Material 3 light/dark themes, editable display names, initials, loading/empty/error states.
- Android screenshot, screen-recording and recents-preview protection using `FLAG_SECURE`. This cannot prevent external cameras, modified clients or compromised devices; it is not end-to-end encryption.
- Firebase Messaging registration, Android permissions, foreground alerts, background delivery and notification tap navigation; per-chat mute and global opt-out.
- Trusted notification dispatch and authenticated account deletion Edge Functions.
- Long-press another person's message to block the sender or report spam, harassment, unsafe content or another concern. Unblock in Settings.

## Windows development

Install Flutter stable (tested with **3.47.7 / Dart 3.13.5**), Git, Android Studio/SDK and JDK 21. Install Android command-line tools, platform tools and the SDK/build-tools requested by Flutter/Gradle. Accept Google's licenses with `flutter doctor --android-licenses`.

```powershell
cd C:\Users\HP\community_connect
flutter doctor -v
flutter pub get
flutter analyze --fatal-infos
flutter test
Copy-Item config/example.json config/local.json
```

Keep `pubspec.lock` committed. Generated files, local configuration, Firebase credentials and signing keys are ignored.

## Supabase

1. Create a **fresh Supabase project**. Enable **Authentication → Sign In / Providers → Anonymous Sign-Ins**. If using optional email login, require email confirmation, set a 12-character password minimum and configure SMTP for verification/reset delivery.
2. Apply **both files in `supabase/migrations/` in filename order** using the SQL editor or Supabase CLI (`supabase link --project-ref YOUR_REF`, then `supabase db push`). Enable the Cron extension first if the project disallows creating it via migration.
3. Allow redirect URL `com.communityconnect.app://auth/callback` in Auth settings. It matches Android's registered callback, independently of the displayed app name.
4. Put the HTTPS project URL and **public publishable key** into ignored `config/local.json`. A legacy `anon` key also works. **Never use `service_role` or `sb_secret_...` in Flutter.** Without compiled Supabase configuration, the APK offers a one-time public configuration form.
5. The migration enables Realtime for `messages`. Table-change delivery uses RLS; chat does not use a global public broadcast channel.
6. Check **Integrations → Cron** and `cron.job_run_details` after deployment.

Run authorization tests on **local/staging Supabase only**, as database owner. Fixtures roll back:

```powershell
psql $env:STAGING_DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/security.sql
```

Tests cover unauthorized reads/writes, expired rooms, sender spoofing, profile escalation, private device registrations, worker RPC access, creator membership, block/unblock, reporting and cascading deletion.

For local PostgreSQL verification without installing a server, install Node.js 24 and run `npm ci`, `npm run test:sql`, and `npm run check:functions`. The SQL harness runs the migrations and assertions in WASM PostgreSQL with a test-only Supabase auth schema. Cron/publication setup is excluded from that harness; hosted Auth, Cron scheduling and Realtime still require real Supabase testing.

Reports are private to their reporter and trusted server operators. Review them in the Supabase dashboard, joining `reports.message_id` to `messages.id`; administrators can remove violating messages or set `profiles.suspended=true`. No client can grant itself moderation privileges. Reports cascade when their messages expire, so no reported temporary-chat content is retained past room deletion.

The database limits each user to three active groups, 20 messages/minute, five device registrations and 2,000 characters/message. Anonymous identity creation can bypass per-user limits. Configure Supabase authentication abuse protection before public rollout; if CAPTCHA is required, add its challenge token to sign-in. This small app is not a complete moderation system.

## Expiry and retention

- PostgreSQL generates `expires_at = created_at + 1 hour`; clients cannot create arbitrary durations or extend them.
- RLS denies listing, joining, reading and sending at expiry. The UI uses server time for its countdown and hides the expired conversation.
- Cron runs every minute. Deleting a room cascades to its messages, memberships and notification jobs. Physical deletion normally follows within one minute. If Cron fails, RLS still blocks access; repair the job to complete deletion.
- The permanent Community chat does not expire. Its messages remain until account deletion or administrative removal.
- Account deletion removes the profile, authored messages, device registrations and groups created by that identity. Supabase backups/operational logs follow the project's separately configured retention; SQL deletion cannot erase pre-existing backups immediately.
- The app does not persist chat history locally. Unsent optimistic messages live in memory and are lost when the app closes.

## Firebase Cloud Messaging

1. Register Android application ID `com.communityconnect.community_connect` in Firebase. Enable the Firebase Cloud Messaging API. The S23 needs working Google Play services.
2. Set the public client fields in `config/local.json`: `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, and `FIREBASE_ENABLED=true`. Explicit `FirebaseOptions` are used; committing `google-services.json` is unnecessary.
3. Give a Firebase service account permission to send FCM messages. Its JSON belongs **only** in the Supabase secret `FIREBASE_SERVICE_ACCOUNT`. Generate a random `PUSH_WORKER_SECRET` and store that as another server secret. Neither secret belongs in the app or Git.

```powershell
supabase functions deploy push-dispatch
supabase functions deploy delete-account
# Your ignored server-only file contains the two secrets above.
supabase secrets set --env-file .env.server.local
```

Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Explicit auth checks protect both endpoints: dispatch requires the worker secret; account deletion validates the caller with `auth.getUser`.

4. Schedule a trusted server to POST `/functions/v1/push-dispatch` once per minute with `Authorization: Bearer YOUR_PUSH_WORKER_SECRET`. See `supabase/schedule-push.example.sql` for Cron/Vault setup. Mobile clients cannot select recipients, devices or notification text.
5. Rebuild the APK, sign in and tap **Settings → Enable notifications**. Grant Android permission. Entering a chat subscribes that identity; its bell button mutes it. Sign-out unregisters the device first.

Messaging 17 uses `register()` / `onRegistered` and registered Firebase Installation IDs (FIDs), including registration refresh events. These are kept in private `device_tokens` rows. The worker uses HTTP v1 with the `fid` target. Notifications contain generic activity text; message content is fetched through RLS after navigation. Before sending, the worker rechecks membership, expiry, suspension, mute and opt-out. Invalid registrations are removed; inactive ones age out after 30 days.

Dispatch is at-least-once: a crash after sending may retry; Android tags collapse the same job. A batch processes 50 recipient jobs, so tune scheduler capacity before a large rollout. Network failures do not silently discard the queue.

References: [Supabase Flutter streams](https://supabase.com/docs/reference/dart/stream), [Firebase Flutter integration](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api).

## Run and install on the S23

Enable **Settings → About phone → Software information → Build number** (tap seven times), then **Developer options → USB debugging**. Connect USB, unlock the phone and accept its authorization prompt.

```powershell
flutter devices
flutter run -d YOUR_DEVICE_ID --dart-define-from-file=config/local.json
flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/local.json
& C:\Users\HP\Android\sdk\platform-tools\adb.exe devices -l
& C:\Users\HP\Android\sdk\platform-tools\adb.exe -s YOUR_SERIAL install -r build\app\outputs\flutter-apk\app-debug.apk
```

If no local config is ready, build using `config/example.json`; the APK will show the setup form. For manual installation, transfer the APK to the phone and open it, allowing installs from that source when Android asks. This is a **development APK**, not a Play Store release.

## GitHub APK builds

The Android workflow runs analysis/tests and produces the ARM64 artifact **ChitChat-S23-APK**. Public configuration may be supplied through repository **Variables** with the names from `config/example.json`. Missing Supabase values enable the setup form. Firebase requires its public values at build time. Backend service secrets never belong in repository variables.

## Signed release

Create a private signing key:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\chitchat-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias chitchat
```

Create ignored `android/key.properties` with `storeFile` (use forward slashes), `storePassword`, `keyPassword`, `keyAlias`. Release builds require that file and do not use debug signing.

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=config/local.json
flutter build appbundle --release --dart-define-from-file=config/local.json
```

See [docs/TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md) for device and backend acceptance checks. Live auth, multi-device chat, Cron, Firebase and screenshot blocking require configured external services and real-device execution; local analysis alone does not verify them.
