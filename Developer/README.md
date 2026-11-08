# Pocket creator tools — hosted web apps

Pocket opens your website inside its SwiftUI shell and provides saved listings, continuity, sharing and a consent-based notification inbox. **You own the interface, backend, database, login and hosting.** The web manifest is listing metadata only. Pocket does not convert interfaces to JSON, build your web app, host code, or automatically share login with your site. Native device capabilities are outside this toolset.

Sharing a Pocket listing controls access to that listing. It does **not** secure your website or APIs. Keep your own authentication and authorization. Plain URL registration is useful without an SDK; notifications require integration with your backend.

## Setup

Node 24+, npm, and Python 3 for local backend integration tests. From the repository root:

```sh
npm --prefix Developer ci --ignore-scripts
npm --prefix Developer run build:browser
npm --prefix Developer test
python3 -m unittest discover -s Tests -p test_manifest.py
```

Tests use disposable local accounts/databases and localhost servers, with no external publication. `npm --prefix Developer test` typechecks the sources, compiles the browser SDK, then runs contract, CLI/MCP, mock, real Python API and example-backend checks. The package stays private; these are checkout tools, not a published npm package.

## Listing manifest

```json
{
  "schemaVersion": "web-v1",
  "creatorKey": "little-notes",
  "name": "Little Notes",
  "summary": "Your own quiet corner for notes and reminders.",
  "entryURL": "https://notes.example/app",
  "iconURL": "https://notes.example/icon.svg",
  "version": "1.0.0",
  "appearance": {"colorScheme": "system", "themeColor": "#48634A"}
}
```

Use HTTPS URLs without userinfo. HTTP loopback URLs are permitted for local development only. Entry URLs can include ordinary web routing queries/fragments. Keep tokens and secrets out of every URL and manifest. `creatorKey` is stable within the owner's account; `version` is your release label, while the server separately assigns a numeric registration revision. Appearance is an optional hint, not a description of your interface.

The [web-v1 contract](Contracts/web-v1/API.md), [schema](Contracts/web-v1/manifest.schema.json), and [exact flow fixtures](Contracts/web-v1/fixtures/flow.json) are shared with the Python and Swift implementations. Existing native v2 contracts are preserved historical references, not the active product direction.

## CLI

```sh
node Developer/src/cli.ts init /tmp/my-web-app
node Developer/src/cli.ts validate /tmp/my-web-app/pocket.manifest.json
node Developer/src/cli.ts preview /tmp/my-web-app/pocket.manifest.json
```

`init` copies a custom static interface and browser SDK into `public/` and creates the manifest without overwriting files. The copied Little Notes example needs its optional example backend for sign-in/reminders; see the walkthrough below. Host/build your web assets with your own tools. `validate` and `preview` only read local JSON. They never fetch URLs, run app code, register listings or claim native execution. Preview prints listing metadata and boundaries; view the actual local interface using the example server or your own development server.

Start Pocket's local API separately with `python3 Backend/server.py --db /tmp/pocket-web.sqlite3`. Create a local Pocket account in the app's account flow. Login credentials are separate from the creator app's own login.

```sh
# zsh: read without echoing or putting the password in command history
read -s 'POCKET_PASSWORD?Pocket password: '; export POCKET_PASSWORD
node Developer/src/cli.ts login --backend http://127.0.0.1:8787 --username creator
unset POCKET_PASSWORD
node Developer/src/cli.ts register /tmp/my-web-app/pocket.manifest.json --backend http://127.0.0.1:8787
```

Only explicit `register` writes listing metadata. Updates by the same owner and creatorKey preserve the server-issued appId and increment revision. Success is reported only after backend confirmation of appId/revision/deepLink. Network failure is not proof of failure to commit; retrying the same owner/key does not create another listing. Changing the registered origin revokes notification integration and requires new credentials and consent.

Basic URL mode remains available:

```sh
node Developer/src/cli.ts register-url https://example.com --name 'Example' --summary 'A website I use' --backend http://127.0.0.1:8787
```

This uses legacy `/apps`, which creates a new listing each time and has no creatorKey update guarantee or notification integration. Use `register` for stable managed listings. Arbitrary sites do not gain native behavior or notification support from being registered.

Account login stores its token in `~/.config/pocket/credentials.json`, mode0600, scoped to the backend origin. Override with `POCKET_CREDENTIALS_FILE`, or provide `POCKET_TOKEN` in the process environment. This is a local credential file, not an OS keychain. HTTPS is mandatory except loopback API development. Redirects are rejected; backend error bodies and credentials are never printed.

## Browser SDK

`npm --prefix Developer run build:browser` emits ordinary JavaScript/declarations to `Developer/dist/browser/`. Copy these files into your site's static assets. No dependency on Node, WebKit globals, Pocket tokens or message handlers is included in the browser entry point.

```js
import { applyAppearance, navigate, pairSubscription } from '/sdk/browser.js';
applyAppearance({colorScheme: 'system', themeColor: '#48634A'});
// Add class="pocket-safe-area" or use --pocket-safe-* CSS variables yourself.
navigate('/notes/42?view=full#content');
await pairSubscription({
  endpoint: '/api/pair', pairingCode: codeFromUser,
  consent: checkbox.checked, csrfToken: yourSessionCSRFToken
});
```

Appearance uses ordinary viewport/theme-color metadata, `color-scheme` and `env(safe-area-inset-*)`. Navigation is normal same-origin web navigation; your website must serve its routes and own back/forward behavior. Pairing POSTs only consent/code to your own same-origin backend, using its own session and CSRF protection. That endpoint returns `{paired:true}` only after successful redemption. It must never accept a client-provided subscription ID as a recipient. The example demonstrates this binding.

For typed listing construction in Node, import `defineWebApp` from `Developer/src/sdk.ts`; it validates metadata and returns a plain JSON value. It does not generate interfaces. The server SDK is a separate import and must never enter browser bundles.

## Notifications: consent, credentials and delivery

1. The listing owner issues an app-scoped credential. Keep it only on the creator backend.
2. A signed-in Pocket user with listing access sees the app name/origin and explicitly allows notifications. Pocket creates a single-use pairing code expiring within five minutes.
3. The user pastes that code into the creator website. Its backend redeems it using the app credential and binds the returned opaque subscriptionId to its **own** authenticated user/session.
4. The creator backend sends bounded events for that subscription. No Pocket account token or username is received by the creator, and the backend cannot target arbitrary Pocket users.
5. Pocket stores an inbox entry. Opening it resolves an authorized event ID to the exact origin-relative target, including query and fragment.

Issue/rotate a credential explicitly; the CLI writes the secret to a new file and reports only its path:

```sh
node Developer/src/cli.ts credential-rotate APP_ID --backend http://127.0.0.1:8787 --out /tmp/notes-app-credential
export POCKET_APP_CREDENTIAL_FILE=/tmp/notes-app-credential
```

The output file must not exist. Keep it outside the repository. A failed rotation can leave an empty reserved file; inspect/remove that empty file before retrying, or choose a fresh path. Rotation immediately invalidates the old credential and outstanding pairing codes; existing subscriptions remain. Restart/update your creator backend with the new secret. `credential-revoke APP_ID --backend ...` revokes the active credential explicitly. The tools never print raw credentials or pass them as CLI/MCP arguments. `POCKET_APP_CREDENTIAL` is an alternative server-only environment value; account `POCKET_TOKEN` is not used for events.

```ts
import { NotificationClient } from './path/to/Developer/src/server.ts';
const notifications = new NotificationClient({
  backend: process.env.POCKET_BACKEND!,
  credential: process.env.POCKET_APP_CREDENTIAL!
});
const subscription = await notifications.redeemPairing(userSuppliedCode);
// Save subscription.subscriptionId against your authenticated creator-app user.
await notifications.send({
  subscriptionId: storedSubscriptionId,
  idempotencyKey: 'note-42-ready', title: 'Your note is ready',
  body: 'Open the note you saved for later.', target: '/notes/42?view=full#content'
});
```

Explicit CLI test (this sends a real inbox event, not a dry run):

```sh
node Developer/src/cli.ts notification-test /tmp/event.json --backend http://127.0.0.1:8787
```

The event JSON has the five fields in the SDK example. MCP `notification-test` takes the same event object. Keep idempotencyKey identical when retrying the same event; within the 30-day retention window, identical retries return the same eventId with duplicate:true. Reusing the key with changed content returns409. No event is sent automatically by validation, preview, registration or login.

Users may mute or revoke subscriptions in Pocket. Muting rejects new events (409); an already accepted event can still be retried idempotently. Revocation invalidates the subscription and its inbox entries. Listing-access removal/app deletion also revokes access. Credential rotation is separate from user preferences. OS notification permission is separate from subscription consent.

Acceptance confirms **inbox storage**, not push or device delivery. Agent 2 owns the local/APNs adapter and native UI. The local walkthrough needs no paid provider, Apple account, deployment or push entitlement. APNs/device delivery remains a separate integration concern.

## Working example

[Little Notes walkthrough](examples/little-notes/README.md) covers registration, its own local login, consent-code redemption, a reminder, and opening `/notes/42?view=full#content`. It uses a small Node/TypeScript creator backend, but your real backend can use any language, database and hosting.

## MCP

Launch `node /absolute/path/to/Pocket/Developer/src/mcp.ts` directly from a stdio MCP client. Do not use `npm run mcp` as a client command: npm's banner pollutes protocol stdout. The newline-delimited JSON-RPC server supports protocol2024-11-05 and exposes `init`, `validate`, `preview`, `login`, `register`, `register-url`, `credential-rotate`, `credential-revoke`, `notification-test`. All use the same services as CLI. Manifest tools accept `manifest`, not the old `configuration` field. Supply credentials via server environment/local credential file only. Mutation tools perform only their explicitly invoked operation.

## Migration and verification boundaries

`build`, `publish`, `plan` and `defineExperience` are obsolete. The CLI returns an actionable error for obsolete commands; there is no implicit conversion to registration. Replace `publish` with `register` using a web-v1 manifest; use your own web bundler for your actual interface. Route examples/build-worker are archived under `legacy/`; old v2 contracts remain unchanged under Contracts. V1 and v2 can still be validated/inspected locally, but cannot register via `/web-apps`. The Python shim forwards supported CLI commands and never maintains a second validator.

Verified: typecheck/browser compilation; shared fixtures; CLI/MCP parity; actual Python registration, pairing, authorization, deduplication, preferences, revocation and launch behavior; creator example own login/CSRF/event/exact-target HTTP flow. Browser visual inspection was attempted but the browser access host was unavailable. Physical-device rendering, safe-area appearance, continuity, notification taps and APNs delivery are not established by these tooling tests. No hosting integration, external deployment, package publication or Apple submission was performed.
