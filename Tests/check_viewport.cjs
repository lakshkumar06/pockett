// The active viewer now lets creators own their viewport/layout entirely.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('Pocket/WebViewer.swift', 'utf8');
const bridge = fs.readFileSync('Pocket/NativeBridge.swift', 'utf8');
const injected = bridge.split('#"""')[1].split('"""#')[0];
assert(!injected.includes('document.')); // Native API injection must not rewrite creator layout.
assert(!source.includes('evaluateJavaScript'));
assert(source.includes('forMainFrameOnly: true'));
assert(!source.includes('websiteDataStore = .default()'));
assert(source.includes('websiteDataStore = .nonPersistent()'));
assert(source.includes('.ignoresSafeArea(.container, edges: .all)'));
assert(source.includes('contentInsetAdjustmentBehavior = .never'));
assert(source.includes('while order.count > 3'));
assert(source.includes('WebPolicy.safe(url, for: app.url)'));
console.log('Web layout ownership and isolated session invariants passed');
