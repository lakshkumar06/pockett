# Pockett

Pocket's iPhone app and creator tools, with a Spacetime backend and a Nemotron miniapp builder. Photon connects the builder to messaging; Vultr can host the gateway and worker.

**Start here:** [Setup and commands](docs/SETUP.md) · [Challenge fit and remaining proof](docs/TRACKS.md) · [Import provenance](IMPORT.md)

- `Pocket/`, `PocketWidgets/`: original iOS app, now able to open generated apps with scoped access.
- `Spacetime/`: durable product state, permissions and workflows.
- `Runtime/`: HTTP gateway, fixed miniapp renderer, Nemotron tool loop and Photon worker.
- `Developer/`: original CLI/SDK/MCP plus build, status, publish, open and cloud deployment commands.
- `deploy/`: Vultr bootstrap, Docker Compose and HTTPS proxy.
- `.env.example`: provider placeholders. `.env` is ignored.

No live provider deployment is implied. The original Python backend below remains for reference and regression checks; run `Runtime/` for this version. See the setup guide for the tested local path and remaining live-provider checks.

---

## Imported Pocket documentation

# Pocket

Pocket is a personal home for creator-hosted web apps: save a website, pin it, reopen it, share its listing and receive consent-based updates in an activity inbox. Creators own their HTML, CSS, JavaScript, authentication, backend and database. Pocket does not host their code, proxy normal website traffic or store their application data.

The app uses SwiftUI and WKWebView (iOS 17+), with a separate WidgetKit library launcher. The account and notification backend uses Python's standard library and SQLite. The creator CLI, browser/server SDKs and MCP tools use Node 24+ and TypeScript. This remains a local testing prototype, not a deployed service or an App Store approval claim.

## Run locally

```sh
npm --prefix Developer ci --ignore-scripts
python3 Backend/server.py
```

Open `Pocket.xcodeproj`, select Pocket and an iPhone simulator, then Run. Alternatively, `./scripts/run-simulator.sh [SIMULATOR_UUID]` builds and launches with local ad-hoc simulator signing (no paid membership). In Pocket's welcome screen, set **Test server** to `http://127.0.0.1:8787`, then create an account. The default database is `Backend/pocket.sqlite3`, ignored by Git. Restart the Python process after updating backend code.

**Home → +** registers an existing website using the compatible basic `/apps` API. Open its details to pin it or share it with another Pocket username. Basic registration supports launching and sharing; notification integration requires a versioned creator manifest. See [creator setup](Developer/README.md), [the Little Notes walkthrough](Developer/examples/little-notes/README.md) and [backend setup](Backend/README.md).

For a physical phone, loopback addresses point to the phone itself. Use the Mac's reachable local network address for the Pocket test API on the same Wi-Fi; creator web-v1 URLs require HTTPS except for simulator loopback development. Existing basic HTTP listings remain compatible. Device signing and App Group provisioning are separate checks.

## Product behavior

- **Home:** pinned apps, recent apps, a Continue card, search and real owned/shared listings. Old device-local bookmarks remain under Earlier bookmarks; mock community discovery is retired.
- **Activity:** unread state, app filters, pagination, exact authorized destinations and per-app notification settings. The inbox works without APNs and refreshes while Pocket is foregrounded.
- **Viewer:** native back/close controls, loading and retry states, safe-area layout and a confirmation before external navigation. Creator layout, zoom and WebKit security remain intact. Pocket never injects account credentials, a native bridge or creator scripts.
- **Reopening:** at most three live web views are kept in memory. A last same-origin URL can be stored per server/account/app; URLs containing common credential query fields or fragments are not persisted. Relaunch reloads a URL, not arbitrary page memory or unsaved forms. Website cookies/storage are ephemeral and disappear when the session is discarded. Sites may require login again.
- **Isolation:** signing out, changing servers or switching Pocket accounts discards web sessions. Observed listing revocation closes its viewer and removes its local resume metadata. Sharing grants access to a Pocket listing, not to a creator's private website account or a public URL's availability. Foreground checks cannot instantly revoke a page while iOS suspends Pocket.
- **Launcher widget:** medium/large app grids with pagination and backend-authorized deep links. It receives listing/icon metadata, never Pocket account credentials. Sign-out/server changes clear its snapshot. Both targets use `group.dev.local.pocket`; physical-device provisioning remains required.

## Notifications

A creator registers a web-v1 manifest, obtains an app-scoped credential and keeps it on their own backend. A user explicitly creates a five-minute pairing code in Pocket, then consents to pairing in the creator's website. That backend redeems the code for an opaque subscription ID. Events require the correct app credential, active listing access and subscription consent. Users can mute or disconnect an app.

Targets are bounded origin-relative paths validated against the registered origin. Opening an inbox item or notification rechecks access with the backend; a push payload cannot select an arbitrary URL. Stable idempotency keys prevent duplicate events. The inbox retains at most 1,000 entries/account for 30 days, with pagination, rate limits and revocation cleanup. A changed registered origin invalidates notification credentials, subscriptions and inbox entries.

Default delivery is explicitly **local test mode**: an accepted event is an inbox entry, not a delivered push. Optional APNs configuration and signing instructions are in [Backend/README.md](Backend/README.md). Website Web Push is not assumed to work inside WKWebView.

## Local demo sequence

Follow the [Little Notes setup](Developer/examples/little-notes/README.md) to start the local API, register the loopback manifest, create its private credential file and run its creator backend. Use Node 24+.

1. Create two disposable Pocket accounts, `alice` and `bob`. Register Little Notes as Alice, then share its listing with Bob in Pocket. Sign in as Bob on the simulator and refresh Home.
2. Open Little Notes, pin it, navigate to its note, close and reopen it. Its separate website demo password is `local-demo-password`. Pocket login does not authenticate the website.
3. In the Pocket listing's details, choose Connect updates, confirm consent and copy the pairing code. In Little Notes, open Connect Pocket reminders, paste it and consent. Choose Send me this note in Pocket.
4. Close the viewer, refresh Activity and open the unread entry. It resolves to `/notes/42?view=full#content`. Mute the subscription and verify new events are rejected; disconnect it and verify a new pairing is required.
5. Re-register a same-origin manifest update as Alice: the app ID stays stable and revision advances. Revoke Bob's listing access, refresh Bob's app and verify the listing/inbox entry is unavailable. Sign out, then sign in as Alice: Bob's website session must not carry over. Test widget and notification links again after terminating Pocket.

These are manual acceptance steps; completed automated checks and unverified UI/device steps are distinguished in [STATUS.md](STATUS.md).

## Migration and checks

SQLite migration 3 preserves existing users, sessions, web listing IDs, shares and native snapshots. `/experiences` is retired (410). Existing native listings appear as unsupported; their data is not silently deleted. Archived native Swift sources under `Pocket/RetiredNative/` are excluded from the shipped targets. Location permissions, background location and the route Live Activity are removed. The library launcher widget remains.

```sh
./scripts/check-local.sh
python3 Tests/test_web_backend.py --http
```

The checks include the creator TypeScript/browser build and actual backend/example integrations, shared web fixtures, Swift URL/deep-link/storage checks, widget regression tests, migration/notification tests, and archived native validation/storage regressions. The default shell must use Node 24+. See [STATUS.md](STATUS.md) for the simulator build and current verification boundaries.

### Visual design and type

Pocket's native interface uses the cream, forest and lime Field Notes direction, with adaptive dark colors and Dynamic Type-aware Cal Sans Text UI. The three bundled fonts are open source (SIL OFL 1.1); provenance and license live in `Pocket/Fonts/`. They load locally and do not affect creator-hosted pages. The welcome illustration is rendered as native vectors. Native forms and navigation retain system accessibility behavior.

Font research: [Cal Sans release history and optical sizes](https://cal.com/font) and [Geist Pixel launch, February 2026](https://vercel.com/blog/introducing-geist-pixel). Cal's UI cut was selected for readable continuous text and a warmer geometric character; Pixel's grid texture did not suit this interface. See `STATUS.md` for build and physical-device verification boundaries.

App icons use creator manifest artwork when it is a supported raster image; otherwise Pocket displays a bundled pictogram. Original prototype Lucide icons are bundled as vector assets (license included). Icon downloads use isolated ephemeral HTTPS requests with a 512 KiB limit and 256-pixel decoding bound. Profile and per-app notification settings use custom SwiftUI layouts with native accessible controls.

The current visual direction is **Folded Worlds**: original bundled abstract sculpture imagery leads Home and welcome, with a quieter companion on Profile and the empty inbox. Live SwiftUI controls and compact app rows sit around the imagery. Art direction, concept-versus-device evidence, asset paths and generation prompts are documented in `Design/ArtDirection/README.md`.
