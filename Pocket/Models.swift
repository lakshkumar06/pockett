import Foundation

enum AppKind: String, Codable { case web, native }

struct MiniApp: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let url: URL
    let community: String
    let summary: String
    var kind: AppKind? = nil
    var runtimeKind: AppKind { kind ?? .web }
    var deepLink: URL { URL(string: "pocket://app/\(id)")! }
}

struct Community: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let summary: String
    let members: Int
}

enum Catalog {
    static let communities = [
        Community(id: "after-hours", name: "After hours", icon: "moon.stars.fill", summary: "Little games. Good company.", members: 24),
        Community(id: "makers", name: "Weekend makers", icon: "hammer.fill", summary: "Small things worth sharing.", members: 38),
        Community(id: "everyday", name: "Everyday club", icon: "sun.max.fill", summary: "Useful things for ordinary days.", members: 16)
    ]
    // Public third-party sites for the starter library; no affiliation or ownership implied.
    static let apps = [
        MiniApp(id: "excalidraw", name: "Excalidraw", icon: "pencil.and.outline", url: URL(string: "https://excalidraw.com")!, community: "makers", summary: "Sketch diagrams and ideas."),
        MiniApp(id: "wikipedia", name: "Wikipedia", icon: "book.fill", url: URL(string: "https://en.m.wikipedia.org")!, community: "everyday", summary: "Read and explore articles."),
        MiniApp(id: "photopea", name: "Photopea", icon: "photo", url: URL(string: "https://www.photopea.com")!, community: "makers", summary: "Edit images in the browser."),
        MiniApp(id: "pomofocus", name: "Pomofocus", icon: "timer", url: URL(string: "https://pomofocus.io")!, community: "everyday", summary: "Run a simple focus timer."),
        MiniApp(id: "diagrams", name: "diagrams.net", icon: "point.3.connected.trianglepath.dotted", url: URL(string: "https://app.diagrams.net")!, community: "makers", summary: "Build flowcharts and diagrams."),
        MiniApp(id: "2048", name: "2048", icon: "square.grid.2x2.fill", url: URL(string: "https://play2048.co")!, community: "after-hours", summary: "Play the original number puzzle.")
    ]
}

enum DeepLink: Equatable {
    case app(String), event(app: String, event: String), community(String), library, activity
    init?(url: URL) {
        guard url.scheme?.lowercased() == "pocket", url.fragment == nil, url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let query = components.queryItems {
            guard url.host == "app", parts.count == 1, query.count == 1, query[0].name == "event", let event = query[0].value,
                  event.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
                  parts[0].range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
            self = .event(app: parts[0], event: event); return
        }
        if url.host == "activity", parts.isEmpty { self = .activity; return }
        if url.host == "library", parts.isEmpty { self = .library; return }
        guard parts.count == 1, parts[0].range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
        switch url.host {
        case "app": self = .app(parts[0])
        case "community": self = .community(parts[0])
        default: return nil
        }
    }
}
