import Foundation

struct WidgetMiniApp: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let shared: Bool
    var icon: Data?
    var deepLink: URL { URL(string: "pocket://app/\(id)")! }
}

struct WidgetSnapshot: Codable, Equatable {
    var account: String?
    var apps: [WidgetMiniApp]
    static let empty = WidgetSnapshot(account: nil, apps: [])

    func page(_ requested: Int, size: Int) -> (apps: [WidgetMiniApp], index: Int, count: Int) {
        let size = max(1, size)
        let count = max(1, (apps.count + size - 1) / size)
        let index = min(max(0, requested), count - 1)
        return (Array(apps.dropFirst(index * size).prefix(size)), index, count)
    }
}

enum WidgetStorage {
    static let group = "group.dev.local.pocket"
    static let kind = "PocketApps"
    static let libraryURL = URL(string: "pocket://library")!
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
    static func read() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: "widget.snapshot"),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: "widget.snapshot")
    }
    static func page(size: Int) -> Int { defaults?.integer(forKey: "widget.page.\(size)") ?? 0 }
    static func setPage(_ page: Int, size: Int) { defaults?.set(page, forKey: "widget.page.\(size)") }
}
