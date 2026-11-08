import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
}
expect(DeepLink(url: URL(string: "pocket://app/hextris")!) == .app("hextris"), "App route")
expect(DeepLink(url: URL(string: "pocket://community/makers")!) == .community("makers"), "Community route")
for link in ["https://app/hextris", "pocket://app", "pocket://app/a/b", "pocket://unknown/id", "pocket://app/hextris?url=https://example.com"] {
    expect(DeepLink(url: URL(string: link)!) == nil, "Reject malformed route: \(link)")
}
expect(Set(Catalog.apps.map(\.id)).count == Catalog.apps.count, "Unique app IDs")
for app in Catalog.apps {
    expect(Catalog.communities.contains { $0.id == app.community }, "Valid community")
    expect(app.url.scheme == "https", "HTTPS app URL")
    expect(DeepLink(url: app.deepLink) == .app(app.id), "Share link round trip")
    let data = try JSONEncoder().encode(app)
    let decoded = try JSONDecoder().decode(MiniApp.self, from: data)
    expect(decoded == app, "Codable round trip")
}
print("Model and deep-link checks passed")

let native = MiniApp(id: "server-id", name: "Route", icon: "map", url: URL(string: "pocket://app/server-id")!, community: "", summary: "Native", kind: .native)
expect(native.runtimeKind == .native, "Explicit native routing")
expect(Catalog.apps.allSatisfy { $0.runtimeKind == .web }, "Legacy routing remains web")
let nativeRoundTrip = try JSONDecoder().decode(MiniApp.self, from: JSONEncoder().encode(native))
expect(nativeRoundTrip.runtimeKind == .native && nativeRoundTrip.deepLink == native.deepLink, "Native backend ID routing round trip")
