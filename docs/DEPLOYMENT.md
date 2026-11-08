# Current deployment

Verified November 8, 2026.

- Spacetime Maincloud database: `pockett-hackutd-laksh`
- Dashboard: https://spacetimedb.com/@krathilakshh/pockett-hackutd-laksh
- Host: `https://maincloud.spacetimedb.com`
- Identity: `c200df6a554301064b002145e68e661005301fb335b67143491e529ff95a0ca1`
- Account uses Maincloud Free's 2,500 TeV monthly credit. After deployment and tests, the dashboard showed 2,499.987 TeV remaining. No paid plan or energy purchase was enabled.
- The private local `.env` points to this deployment. Never copy its service token into the iPhone app.

Accounts, sessions, app listings, shares, jobs, generated app data, notification state and authorization run in Spacetime. The HTTP gateway and NVIDIA worker currently run on the Mac. They still require a separate public compute deployment for use away from this Mac; no Vultr server was provisioned here.

## Run the gateway and worker

With Node 24 active, in separate terminals from the repository root:

```sh
node --env-file=.env Runtime/src/server.ts
node --env-file=.env Runtime/src/worker.ts
```

For the iPhone simulator, use `http://localhost:8787` in Pocket's Test server setting. This connects through the local gateway to the cloud database. A physical iPhone cannot use its own localhost to reach the Mac. A public HTTPS gateway is still needed for a portable demo.

Build for the simulator with signing enabled so Keychain login storage works:

```sh
xcodebuild -project Pocket.xcodeproj -scheme Pocket -configuration Debug \
  -sdk iphonesimulator -derivedDataPath .build/Xcode \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

## Verified flows

- Cloud signup/login, sharing/revocation, CLI build/status/publish/open, leased jobs, generated app data, scoped access, notification pairing, idempotency and inbox passed `Runtime/test/live.ts`. This particular suite uses a model fixture.
- Separately, real NVIDIA Nemotron Lightning created Cloud Groceries through `build_app`, `test_app`, and `finish`; the job and published app were saved in Maincloud.
- The signed iPhone simulator app signed in, listed Cloud Groceries and opened it with a scoped access link. Its saved row survived a gateway process restart and an in-app reload.
- Browser add/delete and reload persistence passed against the same Maincloud app. The iPhone automatically displayed the new Shared apples row through the existing polling flow.
- Direct unauthenticated procedure access failed with `Gateway identity required`; unauthenticated SQL could not access the private users table.

The account and rows used for verification are synthetic test data. The private test fixture is in ignored `.runtime/cloud-app-test.json`; it is not a deployment secret or a credential to distribute. Photon remains disabled. APNs push and a public gateway deployment remain unverified.
