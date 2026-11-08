import SwiftUI

@MainActor final class Store: ObservableObject {
    @Published private(set) var saved: Set<String>
    @Published private(set) var joined: Set<String>
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = Set(defaults.stringArray(forKey: "pocket.saved.v1") ?? ["hextris", "excalidraw"])
        joined = Set(defaults.stringArray(forKey: "pocket.joined.v1") ?? ["after-hours"])
    }
    func toggleSaved(_ id: String) {
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
        defaults.set(Array(saved).sorted(), forKey: "pocket.saved.v1")
    }
    func toggleJoined(_ id: String) {
        if joined.contains(id) { joined.remove(id) } else { joined.insert(id) }
        defaults.set(Array(joined).sorted(), forKey: "pocket.joined.v1")
    }
}

/// Only browsing metadata persists. WebKit's in-memory sessions are discarded on logout.
struct HomeState: Codable {
    var pinned: Set<String> = []
    var recent: [String] = []
    var lastURLs: [String: URL] = [:]
    var lastOpened: [String: Date] = [:]

    private enum CodingKeys: String, CodingKey { case pinned, recent, lastURLs, lastOpened }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pinned = try values.decodeIfPresent(Set<String>.self, forKey: .pinned) ?? []
        recent = try values.decodeIfPresent([String].self, forKey: .recent) ?? []
        lastURLs = try values.decodeIfPresent([String: URL].self, forKey: .lastURLs) ?? [:]
        lastOpened = try values.decodeIfPresent([String: Date].self, forKey: .lastOpened) ?? [:]
    }
}

@MainActor final class HomeStore: ObservableObject {
    @Published private(set) var state = HomeState()
    private var identity: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func use(server: String, account: String) {
        let encoded = (try? JSONEncoder().encode([server, account])) ?? Data()
        let key = "pocket.home.v1." + encoded.base64EncodedString()
        guard key != identity else { return }
        identity = key
        state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HomeState.self, from: $0) } ?? HomeState()
    }
    func clearSession() { identity = nil; state = HomeState() }
    func pin(_ id: String) {
        if state.pinned.contains(id) { state.pinned.remove(id) }
        else if state.pinned.count < 100 { state.pinned.insert(id) }
        persist()
    }
    func opened(_ id: String) {
        state.recent.removeAll { $0 == id }
        state.recent.insert(id, at: 0)
        state.recent = Array(state.recent.prefix(100))
        state.lastOpened[id] = Date()
        persist()
    }
    func remember(_ url: URL, app: String, entry: URL) {
        guard identity != nil, WebPolicy.restorable(url, for: entry) else { return }
        if state.lastURLs.count < 100 || state.lastURLs[app] != nil { state.lastURLs[app] = url; persist() }
    }
    func lastURL(app: String, entry: URL) -> URL {
        guard let url = state.lastURLs[app], WebPolicy.restorable(url, for: entry) else { return entry }
        return url
    }
    func retain(_ ids: Set<String>) {
        let retained = ids.union(Catalog.apps.map(\.id))
        state.pinned.formIntersection(ids); state.recent.removeAll { !retained.contains($0) }
        state.lastURLs = state.lastURLs.filter { retained.contains($0.key) }
        state.lastOpened = state.lastOpened.filter { retained.contains($0.key) }
        persist()
    }
    private func persist() { guard let identity, let data = try? JSONEncoder().encode(state) else { return }; defaults.set(data, forKey: identity) }
}
