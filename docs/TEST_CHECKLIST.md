# ChitChat acceptance checklist

## Local automated

- `flutter pub get`
- `flutter analyze --fatal-infos`
- `flutter test` (setup, public-key validation, optimistic merge, pagination overlap, avatars, navigation and group-name validation)
- `npm ci` then `npm run test:sql` (real WASM PostgreSQL, test-only auth schema, excludes hosted Cron/Realtime wiring)
- `deno check supabase/functions/push-dispatch/index.ts supabase/functions/delete-account/index.ts`
- Staging SQL: `psql ... -v ON_ERROR_STOP=1 -f supabase/tests/security.sql`

## Two physical devices with deployed Supabase

- Continue anonymously on both; confirm different persistent identities after restarting.
- Enter Community chat; send on A and see exactly one authoritative copy on B.
- Disable A's network, send, restore it and retry. Confirm no duplicates after reconnect.
- Tap Spill the Chaya, create a group and confirm creator enters immediately.
- Join the group on B, verify messages, timestamps and earlier-message pagination.
- Leave the group open until expiry. Both devices must hide chat; REST requests using their JWTs must fail to read/write expired content.
- Verify Cron deletes the room, messages, members and queued jobs within its next successful minute.
- Verify client attempts to change expiry, sender or another account's name fail.
- Verify display-name changes and light/dark mode with large Android text settings.
- Long-press a received message, report it and confirm the private report is stored.
- Block its sender; their messages disappear and notifications between you stop. Unblock from Settings and confirm messages are available again.
- Optional email registration, confirmation, login, password reset link and logout.

## FCM with real Firebase configuration

- Grant permission; confirm only the owning user can see the FID registration.
- Test foreground activity banner, background notification and terminated-app notification tap.
- Muted chat and global opt-out receive no new pushes.
- Expired groups and suspended accounts receive no newly dispatched pushes.
- Sign out: the device registration is removed and no subsequent pushes arrive for that identity.
- Test registration refresh, invalid-registration cleanup and worker retry.
- Calling push-dispatch with an ordinary Supabase JWT must return 401.

## Galaxy S23

- Install the ARM64 APK and launch it.
- Attempt hardware screenshot and Android screen recording while chatting; capture should be blocked/blank.
- Verify chat content is hidden in the recent-apps preview.
- Confirm keyboard/composer behavior, back navigation, portrait/landscape and readable dark-mode contrast.
- Delete an account and confirm its data cascades as documented.

Unexecuted items remain unchecked; no successful end-to-end testing is implied.
