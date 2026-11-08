# Little Notes — custom interface + own creator backend

A small local example with its own HTML/CSS/JavaScript interface and Node/TypeScript backend. It uses one demo password, in-memory hour-long sessions and one fixed note. There is no Pocket account token in the website or creator backend. This is a local integration example, not a production authentication/database template. Sessions and subscription bindings reset on restart. A real app should persist its own user-to-subscription mapping and implement production authentication, abuse controls and secure cookies over HTTPS.

From the Pocket repository root:

1. `npm --prefix Developer ci --ignore-scripts`, then `npm --prefix Developer run build:browser`.
2. Start Pocket's local API: `python3 Backend/server.py --db /tmp/pocket-notes.sqlite3`.
3. Create/sign in to a local Pocket account in Pocket. Login the creator CLI using `POCKET_PASSWORD` and `node Developer/src/cli.ts login --username YOUR_ACCOUNT --backend http://127.0.0.1:8787`; unset the password afterward.
4. Register the loopback manifest: `node Developer/src/cli.ts register Developer/examples/little-notes/pocket.local.json --backend http://127.0.0.1:8787`. Save its returned appId. The non-local `pocket.manifest.json` uses placeholder HTTPS URLs; replace them with your own hosting addresses before real use.
5. `node Developer/src/cli.ts credential-rotate APP_ID --backend http://127.0.0.1:8787 --out /tmp/notes-app-credential`.
6. Start the creator backend: `POCKET_APP_CREDENTIAL_FILE=/tmp/notes-app-credential node Developer/examples/little-notes/server.ts`.
7. Open `http://127.0.0.1:8788`. Sign in using the explicitly local demo password `local-demo-password` (override with `NOTES_PASSWORD`).
8. In Pocket, open this registered app's notification settings, consent and copy its pairing code. In Little Notes, open “Connect Pocket reminders,” paste the code and check the consent box. Your browser sends it to this creator backend, which redeems it and stores only the opaque subscription ID in your own example session. It returns `{paired:true}` to the browser.
9. Click “Send me this note in Pocket.” Open the resulting Pocket inbox entry. Its authorized launch URL is exactly `http://127.0.0.1:8788/notes/42?view=full#content`. The creator page serves that route and shows the note. Pocket account login does not log you into Little Notes.

`NOTES_PORT` changes the port; update/re-register the manifest URLs before pairing. A changed origin invalidates notification credentials/subscriptions, so rotate the credential and pair again after an origin update. `NOTES_PUBLIC_DIR` may point at the `public/` directory created by CLI init. `POCKET_BACKEND` overrides the default local Pocket API. This server binds127.0.0.1 only and rejects unexpected Host/Origin/CSRF values. Physical phones need genuinely reachable HTTPS creator URLs, not a phone's loopback address.

The browser uses the compiled browser SDK served at `/sdk/browser.js`. The server SDK runs only in the Node backend. A reminder uses a fixed server-selected note target and session-bound subscription; the caller cannot select another subscription. Browser requests do not include app credentials. Successful sending means inbox acceptance, not APNs delivery.

`npm --prefix Developer test` exercises this entire local HTTP flow using a temporary Python backend, temporary accounts, an ephemeral creator server, CSRF checks, single-use consent, duplicate events and exact target loading. It does not rely on a paid notification provider. Visual/device interactions remain separately unverified when browser/device access is unavailable.
