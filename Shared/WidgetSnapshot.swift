import Foundation

struct WidgetMiniApp: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let shared: Bool
    var icon: Data?
    var origin: String? = nil
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

/// Fixed native layout: text only, scoped to the current account and registered origin.
struct WidgetCard: Codable, Equatable {
    let account: String
    let appID: String
    let origin: String
    let title: String
    let body: String
    let updated: Date
    static func valid(title: String, body: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 60 && body.count <= 180
    }
    func matches(_ snapshot: WidgetSnapshot) -> Bool {
        account == snapshot.account && snapshot.apps.contains { $0.id == appID && $0.origin == origin }
    }
}

extension WidgetStorage {
    static let cardKind = "PocketAppCard"
    static func cards() -> [WidgetCard] {
        guard let data = defaults?.data(forKey: "widget.cards"),
              let cards = try? JSONDecoder().decode([WidgetCard].self, from: data) else { return [] }
        return cards.filter { $0.matches(read()) }
    }
    static func writeCards(_ cards: [WidgetCard]) {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        defaults?.set(data, forKey: "widget.cards")
    }
}
