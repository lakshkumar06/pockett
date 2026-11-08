# Pockett implementation status — 2026-11-08

Implemented and locally checked:

- Spacetime 2.14 module with private tables, publisher-identity enforcement and transactional product logic.
- Existing account/listing/sharing/notification REST flows through the new gateway.
- Nemotron build/test/repair tool loop with persisted jobs and leases; configurable hosted model.
- Photon 2.0 account pairing, persistent conversation context, received-message polling and idempotent replies.
- CLI/MCP build, status, publish, open and Photon-link commands.
- Vultr plan, price-capped provisioning and SSH runtime upload; Docker Compose HTTPS gateway and worker.
- iPhone app automatically obtains per-app access when opening generated miniapps.

Verification completed: existing local regression script, creator tests, runtime type checks and five runtime test groups; real local Spacetime flows including CLI build/status/publish/open; browser add/reload/remove at 390px and 1280px; iOS Simulator build succeeded. NVIDIA responses in tests are fixtures. Photon and Vultr calls are contract/preflight tests, not live deployments.

Not configured: live NVIDIA model/key, Photon project/sender/channel, Vultr instance, Maincloud deployment and APNs. `.env` contains placeholders and is ignored. Setup: [docs/SETUP.md](docs/SETUP.md). Challenge evidence and eligibility limits: [docs/TRACKS.md](docs/TRACKS.md).

---

## Imported baseline status (historical)

# Pocket verification status — November 3, 2026

This describes the current hosted-web revamp. Previous native/runtime and mock-community visual results do not verify this build.

## November 3 — image-led art direction

- Created a three-direction concept board, then implemented Folded Worlds as the working direction: original sculptural folded acetate/paper imagery, image-led Home masthead and compact pinned/library rows. Search, add and Continue remain functional SwiftUI over the artwork. Profile and empty Activity use a quieter original companion image; welcome uses the hero. Removed the earlier primitive-shape welcome illustration.
- Artwork is bundled in `Pocket/Icons.xcassets/pocket-folded-world.imageset` and `pocket-quiet-fold.imageset`. Concept board, design rationale, provenance and prompt set: `Design/ArtDirection/README.md`. Generated mockups are concepts, not app screenshots. Creator-owned pages and app identities remain independent of Pocket artwork.
- Signed iOS build PASS; full local checks PASS (logs `/private/tmp/pocket-art-build.log` and `/private/tmp/pocket-art-checks.log`). Installed successfully on Laksh’s connected iPhone 15 via devicectl after the final build. On-device visual/interaction review remains pending; installation is not visual verification. No simulator used for this work. Existing iPad orientation warning remains.

## November 3 — icon and settings correction

- Replaced app letter placeholders with creator-provided raster icons where available and bundled pictogram fallbacks. Imported all 19 original prototype Lucide SVGs into an Xcode vector asset catalog; verified all 19 names inside the built Assets.car. Lucide license included in app resources. Tab icons, search/add controls and app marks now use those assets.
- Creator icons use a separate ephemeral, cookie/credential-free HTTPS request, 512 KiB encoded limit, 256-pixel thumbnail and request/resource timeouts. Failed or unsupported image formats (including SVG) retain the bundled fallback; no third-party favicon service or Pocket token injection.
- Rebuilt signed-in Profile as a custom scroll composition with account identity, real owned/shared counts, notification controls, library widget preview/instructions, connection editor and sign-out confirmation. Rebuilt notification settings with app identities, per-app toggles and disconnect confirmation. Sharper neutral canvas and stronger icon colors replace the earlier uniformly pastel treatment.
- Verified: complete local checks PASS, signed iOS build PASS, compiled vector assets inspected. Logs: `/private/tmp/pocket-icon-build.log`, `/private/tmp/pocket-icon-checks.log`. Physical iPhone remains unavailable; this revision has not been installed or visually reviewed on device. No simulator launched or controlled.

## November 3 visual implementation

- Implemented the saved Field Notes Figma direction in the actual SwiftUI screens: cream/forest/lime adaptive palette, new Home hierarchy and Continue card, pinned tiles, Activity heading and app marks, welcome pocket artwork, add-app heading, detail typography and shared form styling. Real account/listing/inbox data and existing actions remain wired; no prototype sample content introduced.
- Bundled unmodified Cal Sans Text UI Regular/SemiBold/Bold (SIL OFL 1.1) from pinned upstream commit `d7051f40a2a2fb9883f793e9780eadd709d6d04d`. Dynamic Type-relative native text roles; no remote font requests or changes to creator web typography. Reviewed a local Cal/Avenir typography specimen; this is not an app screenshot.
- Browser presentation has visible back, options, close and loading controls in a bottom safe-area inset. Website content, credential isolation and session policies remain unchanged.
- Verified: complete `scripts/check-local.sh` PASS; signed generic iOS Debug build PASS, including widget; plist/project validation and scoped whitespace checks PASS. All three font PostScript names, font files and license verified inside built Pocket.app. Build retains the existing iPad orientation warning.
- Pending: installation and visual/accessibility review on the physical iPhone (device currently unavailable). No simulator was started for this task. Figma connector remains rate-limited; implementation used the previously saved prototype source/screenshots. No claim of fresh Figma export or device visual verification.
- Logs: `/private/tmp/pocket-design-build.log`, `/private/tmp/pocket-design-checks.log`. Typography specimen: `.build/design-review/typography.png`.

## Implemented

- SwiftUI Home with real owned/shared listings, pins, recents, Continue and preserved earlier bookmarks; Activity inbox with unread state, app filters, pagination and per-app settings; existing accounts and Keychain sessions.
- Isolated ephemeral WKWebView sessions, three-page memory bound, account/server/app-scoped safe URL restoration, back/retry/close controls and explicit external navigation. No credential injection, viewport rewriting or native bridge. Unsaved forms and arbitrary page memory are not restored after termination.
- Central launch handling for app/event/widget links after authentication; backend reauthorization and observed-revocation cleanup. Notification payloads supply IDs, not trusted target URLs.
- Python/SQLite migration 3 preserves accounts, sessions, legacy web IDs, shares and native snapshots. Stable web-v1 registration/update, app credentials, consent pairing, preferences, safe targets, dedupe, pagination, rate limits, retention, device registration/transfer and revocation.
- Inbox independent of push; labelled local adapter and foreground refresh. Optional APNs provider adapter uses environment secrets and system curl/openssl. Optional signed push entitlement is disabled by default.
- Native JSON launching and `/experiences` retired; old listings explicitly unsupported. Route/location/ActivityKit source archived outside target membership; location permissions/background mode and route Live Activity removed. Library launcher widget retained.
- Agent 1's frozen web-v1 contracts consumed without edits. Creator CLI/SDK/MCP and Little Notes integrate with the Python API. Root/backend docs and check script describe the active product.

## Verified in this checkout

- `scripts/check-local.sh` with Node 24.10.0: PASS. Swift model/deep-link, legacy bookmark and account-scoped home persistence/restoration checks; widget pagination/snapshot; creator TypeScript check/browser build; nine Node integration groups; four manifest tests; three base Python backend tests; web backend suite; Swift shared web fixture/URL checks; project/plist/entitlement/syntax checks.
- Archived native regressions retained: ten configuration fixtures, data mapping/limits and private route storage checks pass. These sources are not compiled into the app.
- `python3 Tests/test_web_backend.py --http`: PASS, seven methods after final retention regression additions. Actual HTTP verifies two accounts, stable revisions, credential separation, consent/expiry/single-use pairing, wrong-app rejection, duplicate/conflicting events, mute/re-enable, same-origin update, origin-change invalidation, sharing/revocation, unsafe targets, cursor ownership/pagination, event rate limits, retention, the 1,000-entry cap, dedupe after pruning, queued-delivery suppression, device transfer/logout and migration preservation.
- Creator integration uses actual temporary Python/Node servers. Little Notes verifies separate login/CSRF, consent redemption, secret-free browser responses, event/dedupe and exact `/notes/42?view=full#content` destination. CLI/MCP checks include account credential file mode0600, rejected login, separate-owner IDs and credential rotation/revoke.
- Full unsigned Debug iOS Simulator build: PASS, arm64 and x86_64, including PocketWidgets. Final log has no compiler warnings/errors. Products at `.build/web-home`; session-local logs `/private/tmp/pocket-web-build.log` and `/private/tmp/pocket-web-checks.log`.
- Final build installed/launched on separate **Pocket Web QA** simulator, UUID `8C4E9980-FF6C-4BCB-B068-CA3E836FB9E1`. Existing simulator/iPhone accounts were not changed. Sign-in screen inspected through Device Hub; latest binary launched successfully.
- `git diff --check`: PASS. No deployment, membership purchase, Apple submission, commit or push. Temporary QA web/API servers stopped and temporary credential files removed; existing user backend left alone.

## Pending / limitations

- Device Hub accessibility controls became usable on retry (see below), but coordinate clicks still fail with `noWindowsAvailable`. Activity-tab and website-form interaction, two-account UI logout isolation, widget taps/pagination, cold event links, dark mode, maximum Dynamic Type and iPad layout remain **not interactively verified**. Agent 1's browser visual review was separately blocked by unavailable browser host. Automated model/API/source checks do not substitute for UI checks.
- Physical-device signing/App Group provisioning and APNs credentials were unavailable. APNs provider acceptance, real phone delivery, permission flow, lock-screen/background behavior and notification-tap cold launch remain unverified. Local adapter tests prove inbox processing only, never push delivery. The APNs path needs signed-device validation before use.
- Websites may require fresh login after session eviction or termination. External authentication navigation opens externally after confirmation; its cookies are not copied into Pocket. Sites relying on external-browser SSO or browser-specific features need compatibility testing.
- Listing revocation cannot erase a public website or retract a notification already submitted to APNs. Offline logout clears local sessions immediately, but server device removal requires a successful logout request; payloads are generic and opening reauthorizes. Suspended iOS apps do not poll for revocation.
- This is a local standard-library prototype, not a production scalability/security audit. Public deployment hardening, account recovery, moderation, domain ownership verification and universal links are outside this slice. Creators own website authentication/storage.

## Manual acceptance sequence

Use [README's local demo](README.md#local-demo-sequence) and [Little Notes walkthrough](Developer/examples/little-notes/README.md): create Alice/Bob, register/share, pin/open/reopen, explicitly pair, send an inbox event, tap the exact destination, mute/disconnect, update the manifest, revoke access and verify logout isolation. Repeat widget and notification links from a terminated app after signing in. Physical phones need reachable HTTPS creator hosting; the loopback example is simulator-only. Check accessibility/offline/error flows before treating the new UI as verified.

## Interactive retry — October 31, 2026

- Found a real setup defect: the unsigned simulator app launched but Keychain session saving failed. Rebuilding with local ad-hoc simulator signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`) fixed login. Updated `scripts/run-simulator.sh` accordingly; no credential-storage fallback or paid signing was introduced. Signed simulator build and shell syntax check pass.
- Verified through Device Hub accessibility actions: QA reader sign-in, Home showing the shared listing, sign-in restoration after terminating/relaunching, Little Notes opening in WKWebView, viewer dismissal, Continue, pinning and the explicit notification consent prompt/code generation. Screenshots confirm Home and the creator's separate login page with native viewer controls.
- Redeemed the UI-generated consent code through the creator API and accepted one local inbox event. This tests the UI-to-backend consent path; the creator form itself and inbox tapping are still unverified. No APNs delivery attempted.
- The coordinate-input blocker persists and the tab bar/web content lack actionable accessibility children in this automation session. Remaining interaction checks above still require manual testing.
- QA demo is running for handoff: Pocket API `http://127.0.0.1:18787`, Little Notes `http://127.0.0.1:18788`, isolated Pocket Web QA simulator signed into disposable `qa_reader`. Both QA accounts (`qa_reader`, `qa_owner`) use `local-qa-password`; the website uses `local-demo-password`. These are local test accounts only. The private temporary app credential is in `/private/tmp/pocket-qa-creator-key`, not source control. This supersedes the earlier cleanup note for these QA services only. Existing user backend/accounts remain untouched.
