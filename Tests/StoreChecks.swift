import Foundation

@main struct StoreChecks {
    @MainActor static func main() {
        let suite = "pocket.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = Store(defaults: defaults)
        precondition(initial.saved == ["hextris", "excalidraw"])
        initial.toggleSaved("hextris")
        initial.toggleSaved("excalidraw")
        initial.toggleJoined("after-hours")
        let empty = Store(defaults: defaults)
        precondition(empty.saved.isEmpty, "An empty Library must stay empty after relaunch")
        precondition(empty.joined.isEmpty, "Leaving all communities must persist")
        empty.toggleSaved("2048")
        empty.toggleJoined("makers")
        let restored = Store(defaults: defaults)
        precondition(restored.saved == ["2048"])
        precondition(restored.joined == ["makers"])
        let home = HomeStore(defaults: defaults)
        let entry = URL(string: "https://notes.example/app")!
        let next = URL(string: "https://notes.example/notes/42?view=full")!
        home.use(server: "https://pocket.example", account: "alice")
        home.pin("notes"); home.opened("notes"); home.remember(next, app: "notes", entry: entry)
        home.remember(URL(string: "https://evil.example")!, app: "notes", entry: entry)
        precondition(home.lastURL(app: "notes", entry: entry) == next)
        home.clearSession(); precondition(home.state.recent.isEmpty)
        home.use(server: "https://pocket.example", account: "bob")
        precondition(home.state.pinned.isEmpty && home.state.lastURLs.isEmpty)
        home.use(server: "https://other.example", account: "alice")
        precondition(home.state.recent.isEmpty)
        home.use(server: "https://pocket.example", account: "alice")
        precondition(home.state.pinned == ["notes"] && home.state.recent == ["notes"])
        precondition(home.lastURL(app: "notes", entry: URL(string:"https://changed.example")!) == URL(string:"https://changed.example")!)
        home.retain([]); precondition(home.state.lastURLs.isEmpty && home.state.pinned.isEmpty)
        print("Legacy bookmarks and account-scoped home/restoration checks passed")
    }
}
