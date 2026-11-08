# Run Pockett

Requires Node 24+, Spacetime CLI 2.14+, and Xcode for the iPhone app. `Backend/` is the preserved Python baseline; the active backend is `Spacetime/` plus `Runtime/`.

## Local backend

From the repository root:

```sh
nvm use
npm ci --prefix Developer
npm ci --prefix Runtime
npm ci --prefix Spacetime/spacetimedb
cp -n .env.example .env
spacetime start --listen-addr 127.0.0.1:3000
```

In another terminal, publish the module without deleting existing data:

```sh
spacetime publish pockett-local --server http://127.0.0.1:3000 --module-path Spacetime/spacetimedb --yes=skip-login --no-config
```

Set `SPACETIME_TOKEN` in `.env` to the token of the identity that first published the database. `spacetime login show --token` displays it; keep it private. The module checks that identity before every operation. Use a dedicated identity for this project. Tokens from a local server do not work on Maincloud.

```sh
cd Runtime
npm start
# Separate terminal, also in Runtime/:
npm run worker
```

Open `Pocket.xcodeproj`. Use the gateway URL under Profile → Test server. The simulator can use `http://127.0.0.1:8787`; a physical iPhone needs a reachable HTTPS deployment. Create an account in Pocket. Existing SQLite accounts/data are not imported; the old project is untouched.

## Build an app

Fill in `NVIDIA_API_KEY` and `NEMOTRON_MODEL`, restart the worker. Choose a currently available Nemotron model with function/tool calling. The model is deliberately configurable; an unconfigured provider fails with a setup message, never a fabricated build.

From the repository root:

```sh
export POCKET_PASSWORD='your-password'
node Developer/src/cli.ts login --username your_username --backend http://127.0.0.1:8787
unset POCKET_PASSWORD
node Developer/src/cli.ts build 'A shared grocery list with item, quantity, and bought fields'
node Developer/src/cli.ts status BUILD_ID
node Developer/src/cli.ts publish BUILD_ID
node Developer/src/cli.ts open APP_ID
```

Use `--backend https://your-host` on each command for a remote gateway. `build 'change request' --app APP_ID` edits an existing generated app. Build IDs are returned by `build`. Publication adds the tested app to Pocket. The iPhone client obtains a short-lived app-scoped access link automatically. CLI `open` returns a private link; do not post it publicly. Share the app through Pocket to grant someone their own access. App data stays in Spacetime; shared users see updates on the five-second refresh.

Supported builds are small collaborative lists, numeric trackers and response polls, with up to eight text/number/boolean fields. This is a constrained app compiler, not arbitrary code hosting. The agent calls `build_app`, `test_app`, repairs failures, then `finish`. Tests execute schema checks, JS syntax checks, persistence and access checks. UI behavior is covered by a separate browser smoke test. The user explicitly publishes afterward. It does not claim semantic perfection, universal code generation, or automatic deployment of arbitrary projects.

MCP: configure your editor to run Node 24 with `Developer/src/mcp.ts`. Available tools include `build`, `status`, `publish`, `open`, and `connect-photon` alongside the original creator tools. Set `POCKET_PASSWORD` only for login; service keys belong exclusively in the runtime `.env`.

## Photon 2.0

Provision a Photon project and agent sender for at least one supported messaging channel, then set `PHOTON_API_KEY`, `PHOTON_PROJECT_ID`, and `PHOTON_SENDER_ID`. Restart the worker.

```sh
node Developer/src/cli.ts connect-photon
```

Send the returned one-time `link CODE` command to the agent within five minutes. Then send `build a grocery list`, `status`, `publish`, or `change add a quantity field`. Each sender and conversation is bound separately to the Pocket account. The worker polls the authenticated Photon 2.0 API, persists its cursor and processed IDs in Spacetime, and sends replies with stable idempotency keys. It keeps a one-minute overlap for eventual consistency. Run one Photon poller per project. Outages are retried; provider delays beyond the overlap may require replaying from an earlier cursor.

No public webhook is needed. This integration has contract tests against Photon's documented message shape. It still needs a real configured sender/channel and an end-to-end live message before claiming the Photon track is complete.

## Vultr

Publish the module to Spacetime Maincloud first, using a project-dedicated identity, and update the Spacetime URL/database/token in `.env`. Set `POCKET_DOMAIN`, `POCKET_PUBLIC_ORIGIN=https://YOUR_DOMAIN`, and the single secret `VULTR_API_KEY`. Pass the Vultr region, plan, Ubuntu OS ID, and SSH key ID explicitly when creating the reviewed deployment plan. Your matching private SSH key must be available through your SSH agent. Use a current Ubuntu image supporting `docker-compose-v2`.

```sh
node Developer/src/cli.ts cloud-plan pocket.example.com --out deploy-plan.json --region YOUR_REGION --plan YOUR_PLAN --os-id YOUR_UBUNTU_OS_ID --ssh-key-id YOUR_SSH_KEY_ID
node --env-file=.env Developer/src/cli.ts cloud-deploy deploy-plan.json --max-monthly 10
```

The second command creates a **billable server** after checking live plan availability and base monthly cost against your ceiling. Extra traffic/tax/add-ons are not included. It returns an instance ID. Check its state in Vultr, point the domain's DNS A record at the instance IP, then:

```sh
node Developer/src/cli.ts cloud-upload YOUR_INSTANCE_IPV4
```

Upload uses SSH and starts Docker Compose with Caddy HTTPS, gateway, and worker. Secrets travel over SSH, not cloud-init. First SSH contact uses trust-on-first-use; verify the host key separately for stronger assurance. Spacetime remains the system of record; Vultr hosts compute and generated app pages. Check `https://YOUR_DOMAIN/health`, sign in, build, publish, and open an app. No Vultr instance has been created by this implementation session.

## Checks

```sh
npm --prefix Developer test
npm --prefix Runtime run check
npm --prefix Runtime test
spacetime build --module-path Spacetime/spacetimedb
bash scripts/check-local.sh
# With the local database + gateway running and the configured .env:
node --env-file=.env Runtime/test/live.ts
```

Optional browser check (Chrome installed): set `QA_LINK_FILE` to an ignored local file while running `Runtime/test/live.ts`, then run `QA_LINK_FILE=that-file node Runtime/test/browser.ts`. The fixture contains a temporary app access link; keep it private. Screenshots go to `.runtime/screenshots` by default.

The live test creates synthetic accounts and checks the real Spacetime path. Its model response is explicitly a fixture; it does not spend NVIDIA credits or send Photon messages. APNs remains unconfigured: notifications work through Pocket's inbox while the app is open.
