// The active viewer now lets creators own their viewport/layout entirely.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('Pocket/WebViewer.swift', 'utf8');
assert(!source.includes('WKUserScript'));
assert(!source.includes('addScriptMessageHandler'));
assert(!source.includes('websiteDataStore = .default()'));
assert(source.includes('websiteDataStore = .nonPersistent()'));
assert(source.includes('.safeAreaInset(edge: .bottom'));
assert(source.includes('while order.count > 3'));
assert(source.includes('WebPolicy.safe(url, for: app.url)'));
console.log('Web layout ownership and isolated session invariants passed');
