# Runtime 1 capability catalog

Frozen following Agent 2 agreement. JSON Schema defines all structural bounds. Semantic rules apply in addition:

- Unique screen IDs, source IDs and mapped field names. Screen zero is entry. Navigation references must exist.
- `route.recording`: routeMap, route metric bindings, route.start/stop. distanceMeters and elapsedSeconds are number; status is string. Native runtime owns recording, permissions, confirmation and persistence. Activity types walk/run/cycle are finite labels.
- `liveActivity.route`: requires route.recording; liveActivity.start/stop use only bundled route-summary layout. Availability is subject to OS/device support. No downloaded layout code.
- `data.refresh`: explicit refresh of a declared source. Source must exist; bindings must match declared field names/types. No automatic polling. GET only, HTTPS without credentials, query, fragment or whitespace. No redirects, custom headers, cookies, Pocket token or request body. JSON object response only, streamed byte cap and timeout. Mapping walks only own object keys in declared path, never evaluates expressions. __proto__, constructor and prototype keys are forbidden. Missing/type-mismatched fields fail closed; string values max 500 characters, numbers finite. Backend language/hosting are unrestricted; data sources are optional and public in runtime 1.
- Metadata name/summary and screen titles cannot be whitespace-only. Configurations are at most 65536 UTF-8 bytes.
- No Bluetooth, webviews, embedded scripts, expressions, arbitrary network calls, downloaded transforms or general native API bridge. Creator TypeScript executes only locally when explicitly building a trusted project.

Fixtures in fixtures/valid must pass all implementations; fixtures/invalid must fail. Changes require agreement recorded in both agent logs.
