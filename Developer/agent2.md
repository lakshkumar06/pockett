# Agent 2 coordination — Swift runtime / Python backend

## 2026-10-31 — inspection and pending agreement
- Inspected Pocket, Shared, PocketWidgets, Backend/server.py, Tests, scripts and Xcode project before changes. Existing WebViewer has no message bridge and will remain isolated.
- Agent 1 log `Developer/agent1.md` is not present yet; Contracts directory is not present. Dependent implementation is pending Agent 1's schema, capability catalog, API specification and fixtures.
- Request: please define v2 component/action/binding grammar, limits, route/live-activity capabilities, HTTPS JSON data sources, and publish/get response envelopes. Please specify the TypeScript check command and two compiled example fixture paths.
- Agreement proposed: preserve existing apps/shares as authorization authority; add SQLite experience snapshots keyed by app ID with unique (owner, creatorKey), revisions, optional sourceURL stored without fetching. Native versus web routing uses explicit kind. No native bridge for legacy web apps; Bluetooth unsupported.
- Independent work underway: migration infrastructure and local route-session storage/ActivityKit scaffolding. Agent 2 alone writes this log; will not edit Agent 1 contracts or other Developer files.

## Milestone 1 — agreement
- Read Agent 1 proposal. AGREE to the proposed v2 envelope, flat component/action grammar, route.recording/liveActivity.route capabilities, typed bindings, limits, HTTPS GET-only data sources, and /experiences envelopes exactly as recorded in agent1.md. Please freeze and provide shared schema/fixtures; runtime/backend implementation will consume them.
- Completed independent transactional migration runner (existing SQLite tables unchanged) and scoped private route session storage foundation.
- Data source implementation will reject redirects and use an ephemeral credential-free URLSession, streamed byte limits and explicit refresh only. Route recording requires user confirmation and OS permission; no automatic resume after restart.
- Requested clarification: sourceURL should be HTTPS without userinfo (stored only). Native /apps listing will expose kind:"native", revision, creatorKey and url:null; legacy kind:"web" retains URL. Please record this in API contract or request adjustment.

## Milestone 2 — native/backend implementation
- Read frozen schema, API, capability catalog and Agent 1 milestone 1. Accept strict sourceURL rule without credentials/query/fragment/whitespace, stored only.
- Backend now exposes POST/GET /experiences, owner+creatorKey upsert, stable IDs/revisions, snapshots, native/web listings and existing sharing/deletion authority. Available for Agent 1 integration via `python3 Backend/server.py --db <temporary.sqlite3>`; backend handler checks currently pass.
- Swift uses the bundled Agent 1 schema plus catalog semantic checks. Native renderer, route storage/recording, explicit consent, credential-free bounded data fetches and compiled ActivityKit layout implemented; compilation/fixture verification underway.
- Found copied Swift module cache referring to old checkout; local checks now use a fresh runtime-v2 cache directory.
- No contract changes made. No external deployment.

## Milestone 3 — validation
- Read Agent 1 milestone 2. Backend tests pass for both shared examples, publishing revisions, independent owners, sharing/revocation, cascade deletion, legacy records and idempotent migration. Swift fixture and route-storage isolation tests pass.
- Full unsigned simulator build PASSED for arm64 and x86_64, including launcher widget and ActivityKit layout, after authorized retry outside sandbox (SwiftUI plugin sandbox failure initially).
- Combined checks now invoke `npm --prefix Developer test`; awaiting/currently running Agent 1 integration tests. Simulator UI smoke work underway. Physical-device/background/signing verification remains unavailable.
- Combined check found shell Node 20; using installed Node 24.10.0. Added an explicit Node >=24 preflight to check-local.
- Request: Tests/Developer/backend.test.ts finally awaits an already-fired child exit when sandbox denies startup, leaving npm test hanging. Please guard exitCode/signalCode before awaiting exit. Will run integration outside sandbox as required for localhost sockets.
- Computer-use session was stopped by user/tool. Simulator UI smoke checks cannot proceed this turn; no bypass attempted. Build/API/fixture checks continue independently.

## Milestone 4 — integrated checks and final boundaries
- Read Agent 1 final handoff; all agreed contracts preserved, no interface changes requested.
- Combined check-local PASS under Node 24.10.0 with authorized localhost sockets: 8 Node groups, 3 manifest tests, 10 Swift shared fixtures, typed data response/credential-isolation/limit checks, route storage isolation, model/store/widget checks, Python backend lifecycle/migration tests and plist/syntax checks.
- Final native simulator build PASS for both architectures including compiled ActivityKit layout. Fixed account-wide stored-route cleanup and stale-session response handling; capability changes stop recording and expanded sets require consent.
- README, Backend README and STATUS now describe actual implementation and validation. UI verification remains blocked by stopped computer-use session; physical-device GPS/background/signing unverified. No external deployment.
- Agent 2 edited only owned runtime/backend/project/scripts/tests/root docs plus this coordination log. Agent 1 contracts and tooling were not edited by Agent 2.

## Final verification
- Final check-local passed, including data-source tests and account-wide cleanup assertions. Final unsigned simulator rebuild passed with no reported compiler warnings/errors.
- Migration runner now explicitly begins an immediate transaction before DDL; injected migration-failure test confirms DDL rollback and unchanged migration records. Backend suite rerun passed; diff whitespace checks clean.
- Re-read Agent 1 final handoff after this milestone. No pending interface disagreement. Remaining work is interactive simulator/device verification only, blocked this turn by the stopped computer-use session; device GPS/background/signing remain unavailable.

## Remote handoff — October 31, 2026
- User authorized committing/pushing completed work to origin. Fetched origin; main was in sync before commits.
- Include Agent 1's completed shared contracts/tooling unchanged alongside Agent 2 runtime/backend/tests/documentation; both are required for the integrated build.
- Prior local checks and unsigned simulator build passed; device/UI limitations remain documented in STATUS.md.
- Another session created integrated commit f385c91 and published feat/native-experiences-creator-tools during handoff. Agent 2 preserved that branch/commit and adds only this coordination record. Main remains unchanged.

# Web home revamp — active coordination (2026-10-31)
- Inspected current web viewer, views/store/account client/app lifecycle, native route code, backend, tests/scripts and STATUS before editing. Native runtime will be removed from shipped sources, historical SQLite snapshots preserved as unsupported listings. Legacy /apps IDs, sessions, sharing and deep links remain.
- Request Agent 1: please define/freeze versioned WEB registration and exact API/fixtures now: owner+creatorKey upsert, app-scoped credential issue/revoke, user-consented subscription pairing code create/claim, subscription prefs/revoke, creator event with idempotencyKey + subscriptionId + bounded title/body + same-origin target, paginated inbox + read/open, device registration/logout cleanup. Need exact endpoint names/envelopes/status codes for Swift/Python/CLI parity.
- Proposed constraints: HTTPS registered entryURL (legacy HTTP remains supported), exact scheme/host/effective-port target origin; no userinfo/controls/backslashes/scheme-relative URLs; creator bearer credential scoped to one app and never exposed to web content. Pairing initiated only by signed-in Pocket user with listing access and explicit consent; one-use short expiry code; creator claims using its app credential. No arbitrary username notification targeting.
- Proposed bounds: 64-char idempotency key, 120 title/500 body, 10-minute pairing, 1000 inbox/account and 30-day retention, 60 events/app/minute, 20/subscription/minute, 50 page size. Inbox is authoritative; local adapter labels delivery as local-only, APNs best effort separately. Please settle contracts and fixtures in your owned files; I will implement independent UI/session/native-retirement scaffolding meanwhile.

## Web milestone 1 — contract agreement / additions requested
- Read web-v1/API.md, manifest.schema.json and fixture inventory. AGREE to registration, exact credential/pairing/subscription/event endpoints, 300-second pairing, title80/body240, strict origin-relative targets, consent/auth/dedupe rules as proposed. Please freeze those portions; implementing them now.
- Required additions before dependent inbox/device work: GET /notification-inbox?limit=1..100&before=<opaque cursor>&appId=<optional> -> existing entries plus nextCursor:null|string and unreadCount total authorized unread; stable newest-first cursor ordering. Default100; 1000/account cap; 30-day retention; idempotency keys retained30 days even if inbox capped.
- Proposed device API: POST /notification-devices {deviceId: UUID,token: hex64..512,environment:"sandbox"|"production"} -> {ok:true,deliveryMode:"local"|"apns"}; DELETE /notification-devices/:deviceId -> {ok:true}. Bind device to current session/account, transfer ownership on registration, delete on logout; never log tokens. Please confirm/freeze or adjust.
- Rates proposed mandatory: events60/app/minute and20/subscription/minute; pairing5/user/app/minute; credential rotation10/app/hour. 429. Existing accepted idempotent retries should bypass event creation rates.
- Independent work: native sources archived under Pocket/RetiredNative (excluded from shipped target next), location/background/Live Activity plist keys removed; new pure safe-origin and account-scoped home/restoration metadata scaffolding.

## Web milestone 2 — API implementation
- Read Agent 1 frozen additions and fixtures. AGREED, including credential DELETE/rotation invalidating outstanding codes. Device API uses the agreed deviceId shape, not installationId.
- Implemented web-v1 registration/update, credentials, consent pairing/redemption, preferences/revocation, idempotent bounded event acceptance, safe targets, cursor inbox/read/authorized launch, device ownership and cleanup in Python. SQLite migration3 preserves old native snapshots; /experiences now410 and old native listings supported:false.
- Origin change invalidates notification integration. Existing /apps/share IDs preserved. Source files for native runtime archived/excluded rather than deleting historical definitions/regression tests. UI/session work in progress.

## Web milestone 3 — integrated verification and simulator
- Read Agent 1 web milestones 2/3. Combined check-local PASS: 9 Node groups, 4 legacy validator cases, 10 archived native fixtures, archived data/storage regression, 3 backend legacy/migration cases, 6 new notification lifecycle cases, new Swift shared-flow/safe-launch checks and syntax/plists.
- Full unsigned iOS Simulator build PASS arm64/x86_64. No route/ActivityKit source or location/background permission in shipped targets. Launcher widget retained.
- New QA-only simulator and temporary database created (existing simulator accounts and connected phone untouched). Actual UI inspection now available via Device Hub, working through home/web/inbox flows. APNs remains unverified; local adapter labels status local-only, never delivered.
- Backend includes environment-configured APNs adapter using system curl HTTP2/openssl (no new Python framework/package), bounded retry outbox and token-safe logs; missing configuration returns configuration-error. Device logout/transfer and consent/access rechecks tested.

## Web final handoff — verification and remaining boundaries
- Read Agent 1 web final handoff after final milestone. Agreement complete; no contract changes requested or pending. Agent 1 contracts/files untouched (this Agent 2 log remains the standing ownership exception).
- Completed active Swift web Home/Activity/viewer, isolated bounded sessions and safe restoration, auth/deep-link/notification routing, consent/settings UI, backend registration/inbox/devices/rates/retention/revocation, optional APNs adapter and labelled local mode. Retired native target membership/location/Live Activity; migration preserves records and unsupported listings. Library widget retained.
- Full local checks PASS with Node24: nine creator groups, four manifest tests, Swift/model/store/widget/shared fixtures, base/web Python suites, archived native regressions, plist and syntax. Final additional live-HTTP web suite PASS (7 methods), including 1000-entry cap and queued-event suppression after pruning/revocation. Full unsigned arm64/x86_64 simulator build PASS without compiler warnings/errors; final binary installed/launched on isolated Pocket Web QA simulator.
- README, Backend/README and STATUS reflect hosted-web product, local demo and actual limits. Temporary QA servers stopped/credential files removed. Existing user backend and original device accounts untouched.
- Blocker: Device Hub coordinate input fails noWindowsAvailable despite screenshot access; only sign-in visually inspected. Main UI, cookie-isolation interaction, widget/cold-link interaction and accessibility need manual verification. Physical signing/App Group/APNs credentials unavailable; real push/device/background behavior NOT verified. Local inbox acceptance is never claimed as delivered push. No deployment, purchase, Apple submission, commit or push.


## Web UI retry milestone
- Re-read Agent 1 final handoff. No interface changes needed.
- Retry exposed unsigned-simulator Keychain save failure. Local ad-hoc simulator signing fixed it; updated run-simulator.sh and README (no insecure session fallback). Signed simulator build and shell syntax/diff checks pass.
- Device Hub AX verified login, restart restoration, shared Home listing, web launch/dismissal, Continue, pinning and consent code creation. Redeemed that consent code and accepted a local event through creator API. Home and website login screenshots inspected.
- Coordinate clicks still fail noWindowsAvailable; Activity tab and website form have no actionable AX children. Remaining interactive account isolation/widget/notification tap/device/APNs checks stay pending. Updated STATUS with exact verification and running disposable QA demo details. No contract edits, deployment or push.

## November 3 — Field Notes visual implementation
Read Agent 1 final handoff before changes and after the visual milestone. Agreement: web-v1 remains frozen, no shared interface or fixture edits needed. Completed adaptive forest/cream/lime native styling, Cal Sans Text UI font bundling/license/provenance, Dynamic Type roles, Home Continue/pins, Activity app marks, welcome vector artwork, add/detail/form typography and visible browser controls. Existing account, sharing, inbox and session transports unchanged. Complete local checks and signed generic iOS build PASS; fonts verified inside app bundle. Requested changes: none. Blockers: Figma Starter tool quota prevents fresh design context; saved prototype source/screenshots used. Physical iPhone unavailable, so no new install or on-device visual verification. No simulator started, deployment, purchase, commit or push. README and STATUS reflect actual evidence.

## November 3 — icon and Profile correction
Re-read Agent 1 handoff; no shared contract changes requested or made. Implemented original prototype SVG asset catalog (19 compiled assets verified), creator icon rendering with bounded credential-free ephemeral transport and pictogram fallbacks, composed Profile/connection/widget screens, and custom per-app notification settings with disconnect confirmation. User feedback supersedes the earlier muted visual treatment. Full local checks and signed iOS build PASS. Blocker: physical iPhone unavailable; not installed or visually verified. No simulator use or external deployment. STATUS updated with exact limitations.

## November 3 — original imagery / composition
Read Agent 1 handoff; no interface dependency or contract change. User rejected superficial styling and requested images/abstract graphics. Generated three visual directions and original text-free production artwork with the built-in image tool. Implemented working Folded Worlds direction: image-led live Home masthead, compact pinned/library rows, image-led welcome and companion imagery for Profile/empty Activity. Preserved real data/actions, backend interfaces and creator content. Assets/prompts/provenance in Design/ArtDirection and Pocket/Icons.xcassets. Build/local check evidence in STATUS; device appearance still pending. No simulator use, deployment or purchase.

User explicitly selected 01 — Folded Worlds after reviewing the three-direction concept board. Selection recorded in Design/ArtDirection/README.md.

Final signed build passed; device reconnected and devicectl successfully installed dev.local.pocket on Laksh’s iPhone 15. No launch or visual verification claimed. User can open Pocket to review.
