# Native capabilities

Pocket injects `window.pocketNative` into the main frame of hosted apps. No SDK or backend credential is needed. Calls return promises through WebKit’s reply handler. In a normal browser, the object is absent.

```js
if (window.pocketNative) {
  const supported = await pocketNative.capabilities();
  await pocketNative.haptics.tap();
  const motion = await pocketNative.motion.sample();
  const walking = await pocketNative.pedometer.today();
}
```

Call from a user-facing button and catch rejected promises. `capabilities()` returns `{version: 1, haptics, motion, pedometer}` availability flags (plus `location`, `backgroundLocation`, and `widgets`); availability is not permission. Hardware still determines whether haptic feedback is felt.

- `haptics.tap()`: medium native impact feedback; resolves `{ok: true}`.
- `motion.sample()`: one Core Motion sample with `attitude` (roll/pitch/yaw in radians), `gravity` and user `acceleration` (x/y/z in g). Stops the sensor after the sample.
- `pedometer.today()`: Core Motion step history from local midnight until now. Returns `steps`, nullable `distanceMeters`, and `from`/`to` Unix milliseconds. iOS also asks for Motion & Fitness permission.

- `location.start()`: asks for native consent every time and starts one native route recording, including while the screen is locked or Pocket is backgrounded. Core Location asks for When In Use permission; Pocket enables the location background mode and system background indicator. Only one app may record at a time (`recording_busy` otherwise).
- `location.read()`: returns `{recording, status, accuracy, points}` for the calling app; `points` contain latitude, longitude, accuracyMeters, and timestamp (Unix milliseconds). `accuracy` is `full` or `reduced` for a recorded route. An app with no route receives `{recording: false, status: 'idle', points: []}`. Reading after leaving/reloading requires fresh consent.
- `location.stop()`: ends that app’s recording without an extra permission prompt. Pocket also displays a native Stop control in the viewer and library.
- `widgets.update({title, body})`: publishes a fixed native text card (title up to 60 characters, body up to 180). Requires app consent and membership in the signed-in library. Returns `{ok: true, requiresUserInstallation: true}`. Add **Pocket app card** from the iOS Home Screen widget gallery, then edit the widget to choose the app. Small and medium sizes are supported. iOS controls refresh timing; the call requests a reload, not immediate display.
- `widgets.clear()`: removes the app’s published card. Published text survives leaving the viewer; signing out clears it. Cards are bound to account, app ID and registered origin, and are excluded when any of these no longer match.

```js
await pocketNative.location.start(); // start from a visible button; native confirmation follows
// Lock the screen, move, then return to the app:
const route = await pocketNative.location.read();
await pocketNative.location.stop();
await pocketNative.widgets.update({title: 'Walk complete', body: 'Your route is ready'});
```

Background recording is a deliberate exception to normal bridge teardown: collection stays native while JavaScript is suspended. No background JavaScript or automatic network uploads run. Recording stops at eight hours, when iOS pauses updates, when permission is revoked, or on account/session reset. The latest 1,000 points remain in memory; they are lost if iOS terminates Pocket or the user force-quits it. There is no automatic restart. Native location respects reduced accuracy and disabled Location Services. This is bounded session recording, not durable all-day tracking.

Pocket presents native consent naming the app and its host before each capability's first use. Grants and denials last only until navigation, leaving the viewer, backgrounding, or session disposal. Apps cannot grant themselves access. The bridge requires an active, visible viewer, HTTPS, an exact registered origin (including port), and the main frame. HTTP development pages and iframes cannot call it. Requests are serialized, limited to four starts per second, and time out after 60 seconds, including consent time. Stop and widget-clear calls bypass consent and rate limits so cleanup remains available. Backgrounding or navigation cancels pending replies; stale sensor callbacks are ignored. An already-started native route continues until stopped.

Promise rejection messages: `untrusted_or_inactive`, `invalid_request`, `busy`, `rate_limited`, `permission_denied`, `unavailable`, `sensor_error`, `cancelled`, `timeout`, `recording_busy`. No arbitrary native method names, files, account credentials, or unrestricted background service access are exposed. New capabilities require a compiled Swift implementation and an explicit allowlist/consent entry in `Pocket/NativeBridge.swift`.

Host `Developer/examples/native-sensors/index.html` on HTTPS and add its URL to Pocket to try the capabilities. Physical-device checks are needed for actual sensor values, haptics, and system permissions; simulators may report sensors unavailable. Test denial, leaving during a request, backgrounding, reload, and an iframe trying the raw WebKit handler. This implementation does not establish App Store approval for third-party native capability access.

Device verification: start recording, lock the phone for a short walk, return and read the route, then stop. Repeat with approximate location, denied permission, and account sign-out. Add a card widget, publish text, then confirm sign-out removes its content after WidgetKit reloads. Simulator/build checks cannot establish background delivery or widget refresh timing.

Platform references: [Apple background location](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates), [configurable widgets](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget).
