import Foundation

@main struct WidgetChecks {
    static func main() throws {
        let rows = (0..<19).map { WidgetMiniApp(id: "app-\($0)", name: "App \($0)", shared: $0 % 2 == 0) }
        let snapshot = WidgetSnapshot(account: "test", apps: rows)
        for size in [4, 8] {
            let pages = snapshot.page(0, size: size).count
            let reached = (0..<pages).flatMap { snapshot.page($0, size: size).apps.map(\.id) }
            precondition(reached == rows.map(\.id), "Every app must be reachable exactly once")
            precondition(snapshot.page(100, size: size).index == pages - 1)
            precondition(snapshot.page(-10, size: size).index == 0)
        }
        precondition(WidgetSnapshot.empty.page(7, size: 4).apps.isEmpty)
        precondition(WidgetSnapshot.empty.page(7, size: 4).index == 0)
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: encoded)
        precondition(decoded == snapshot)
        for row in rows { precondition(DeepLink(url: row.deepLink) == .app(row.id)) }
        precondition(DeepLink(url: WidgetStorage.libraryURL) == .library)
        precondition(DeepLink(url: URL(string: "pocket://library/unexpected")!) == nil)
        print("Widget pagination, snapshot and launch-link checks passed")
    }
}
