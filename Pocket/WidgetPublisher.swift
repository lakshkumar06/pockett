import UIKit
import WidgetKit

/// Only public-facing listing data crosses into the widget. Session tokens stay in Pocket.
@MainActor enum WidgetPublisher {
    private static var iconTask: Task<Void, Never>?
    private static var generation = UUID()

    static func clear() {
        generation = UUID()
        iconTask?.cancel()
        WidgetStorage.writeCards([])
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.cardKind)
        WidgetStorage.write(.empty)
        WidgetStorage.setPage(0, size: 4)
        WidgetStorage.setPage(0, size: 8)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
    }

    static func updateCard(app: MiniApp, title: String, body: String) -> Bool {
        let snapshot = WidgetStorage.read()
        guard let account = snapshot.account, let origin = WebPolicy.origin(app.url),
              snapshot.apps.contains(where: { $0.id == app.id && $0.origin == origin }),
              WidgetCard.valid(title: title, body: body) else { return false }
        var cards = WidgetStorage.cards().filter { $0.appID != app.id }
        cards.append(WidgetCard(account: account, appID: app.id, origin: origin, title: title, body: body, updated: Date()))
        WidgetStorage.writeCards(cards)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.cardKind)
        return true
    }
    static func clearCard(app: MiniApp) {
        WidgetStorage.writeCards(WidgetStorage.cards().filter { $0.appID != app.id })
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.cardKind)
    }

    static func publish(_ apps: [RegisteredApp], account: String, server: String) {
        iconTask?.cancel()
        let revision = UUID()
        generation = revision
        let identity = server + "|" + account
        let previous = WidgetStorage.read()
        let cached = previous.account == identity ? Dictionary(uniqueKeysWithValues: previous.apps.map { ($0.id, $0.icon) }) : [:]
        let rows = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map {
            WidgetMiniApp(id: $0.id, name: $0.name, shared: $0.owner != account, icon: cached[$0.id] ?? nil, origin: $0.url.flatMap { WebPolicy.origin($0) })
        }
        var snapshot = WidgetSnapshot(account: identity, apps: rows)
        if snapshot != previous {
            WidgetStorage.write(snapshot)
            WidgetStorage.writeCards(WidgetStorage.cards())
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.cardKind)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
        }
        iconTask = Task {
            for index in snapshot.apps.indices {
                guard !Task.isCancelled, generation == revision else { return }
                guard snapshot.apps[index].icon == nil,
                      let source = apps.first(where: { $0.id == snapshot.apps[index].id }),
                      source.kind != .native, let sourceURL = source.url,
                      let url = URL(string: "apple-touch-icon.png", relativeTo: sourceURL)?.absoluteURL else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
                let client = URLSession(configuration: configuration)
                defer { client.invalidateAndCancel() }
                guard let (data, response) = try? await client.data(for: request),
                      let response = response as? HTTPURLResponse, response.statusCode == 200,
                      data.count < 4_000_000, let image = UIImage(data: data),
                      image.size.width > 0, image.size.height > 0 else { continue }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format)
                snapshot.apps[index].icon = renderer.pngData { _ in
                    image.draw(in: CGRect(x: 0, y: 0, width: 128, height: 128))
                }
            }
            guard !Task.isCancelled, generation == revision else { return }
            if WidgetStorage.read() != snapshot {
                WidgetStorage.write(snapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
            }
        }
    }
}
