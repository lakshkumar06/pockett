# Pocket metadata and notification backend

Python 3.9+ standard library and SQLite; no application hosting, arbitrary URL fetching, website proxy or creator database. Use throwaway credentials on a trusted network when testing over HTTP. This development server is not hardened for public internet exposure.

```sh
python3 Backend/server.py --host 0.0.0.0 --port 8787
```

Default database: `Backend/pocket.sqlite3` (ignored). Without `--host`, the server binds loopback. Set the same backend address on both Pocket devices. Simulator loopback works; an iPhone needs the Mac's reachable local address on the same Wi-Fi, local-network permission and firewall access. USB alone does not establish that route.

Create two accounts, register a website in Home, open its details and grant access to the second username. Refresh the second account, launch, revoke from the first and refresh again. Sharing controls the listing; website authorization remains the creator's responsibility.

## API and migration

The exact active API and shared fixtures are owned by Agent 1: [web-v1 contract](../Developer/Contracts/web-v1/API.md). Account routes `/signup`, `/login`, `/me`, `/logout` and existing `/apps`, `/apps/:id`, `/apps/:id/shares` remain compatible. Passwords use salted scrypt; random session tokens are hashed in SQLite and expire after seven days. Pocket keeps them in Keychain.

- `/web-apps`: versioned manifest registration/update, stable owner+creatorKey ID, increasing revision and authorized manifest read.
- `/apps/:id/notification-credential`: owner-only rotation/revoke, app-scoped secret returned once and stored hashed.
- `/apps/:id/pairings` and `/notification-pairings/redeem`: explicit consent, expiring single-use code and app-authenticated redemption.
- `/notification-subscriptions`: account preferences and disconnect.
- `/notification-events`: creator-authenticated, consent/access checked, safe targets, idempotency and rate limits.
- `/notification-inbox`: authorized paginated history, unread count, read marking and launch resolution.
- `/notification-devices`: account/session-bound installation registration, transfer and deletion. Logout removes that session's devices. No device tokens are logged or returned.

Migration 3 adds tables without replacing existing accounts, listings, sessions, shares or snapshots. Native listings remain visible as unsupported; `/experiences` returns 410. The old native contract and database migration remain historical references. SQLite transactions protect upserts, single-use pairing and idempotency. Retention cleanup runs on API requests and in the delivery worker: 30-day inbox/idempotency retention, 1,000 inbox entries/account, bounded devices and expiring pairing codes. Revocation cascades subscriptions, inbox and queued delivery. Origin changes revoke credentials and pairings too.

## Delivery modes

The default `POCKET_PUSH_ADAPTER=local` processes queued work as `local-only`. It never sends or simulates an APNs notification. Foreground inbox refresh works independently of device registration. This is the tested mode.

Optional APNs adapter configuration:

```sh
export POCKET_PUSH_ADAPTER=apns
export APNS_KEY_ID=YOUR_KEY_ID
export APNS_TEAM_ID=YOUR_TEAM_ID
export APNS_PRIVATE_KEY_PATH=/private/path/AuthKey.p8
export APNS_TOPIC=YOUR_POCKET_BUNDLE_ID
python3 Backend/server.py
```

Keep the `.p8` file outside the repository with private permissions. The adapter uses installed `openssl` and HTTP/2-capable `curl`, with TLS validation enabled. JWTs/device tokens are passed to curl through stdin, not command arguments or logs. Device registrations select sandbox/production. The worker rechecks access, consent and session validity before submission, retries transport/429/5xx failures at most three times and removes devices rejected with 410. A recorded `provider-accepted` result means APNs accepted the request, not proof the phone displayed it. Already submitted notifications cannot be recalled.

The normal Pocket build has push disabled. To test actual APNs, configure a suitable signed App ID/provisioning profile, build with `CODE_SIGN_ENTITLEMENTS=Pocket/PocketPush.entitlements`, `POCKET_PUSH_ENABLED=YES`, and `POCKET_APNS_ENVIRONMENT=development` (or production for production signing). Match `APNS_TOPIC` to the actual bundle ID. Preserve the App Group on both targets. In Profile, explicitly enable device notifications. Notification taps carry only IDs and fetch an authorized launch target after authentication. No website is given a native message bridge or Pocket credential.

See Apple's [APNs command-line guidance](https://developer.apple.com/documentation/usernotifications/sending-push-notifications-using-command-line-tools). Signing, real APNs acceptance, device delivery, lock-screen behavior and background/cold notification launches remain unverified. No membership purchase or external deployment was performed.

## Verification

```sh
python3 Tests/test_backend.py --http
python3 Tests/test_web_backend.py --http
./scripts/check-local.sh
```

Tests cover two accounts, ownership/sharing/revocation, stable updates, consent, pairing expiry/scope, credential rotation/revoke, unsafe targets, duplicate/conflicting events, pagination, rates, retention, device transfer/logout, local adapter behavior and legacy migration preservation. The creator checks also exercise the Little Notes backend's own login/CSRF and exact notification destination. See [STATUS.md](../STATUS.md) for limitations.
