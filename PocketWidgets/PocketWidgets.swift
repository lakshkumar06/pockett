import SwiftUI
import WidgetKit
import AppIntents

struct PocketEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PocketProvider: TimelineProvider {
    func placeholder(in context: Context) -> PocketEntry {
        PocketEntry(date: .now, snapshot: WidgetSnapshot(account: "preview", apps: [
            WidgetMiniApp(id: "focus", name: "Tiny Focus", shared: false),
            WidgetMiniApp(id: "notes", name: "Notes", shared: true),
            WidgetMiniApp(id: "draw", name: "Sketch", shared: false),
            WidgetMiniApp(id: "play", name: "Word game", shared: true)
        ]))
    }
    func getSnapshot(in context: Context, completion: @escaping (PocketEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : PocketEntry(date: .now, snapshot: WidgetStorage.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PocketEntry>) -> Void) {
        completion(Timeline(entries: [PocketEntry(date: .now, snapshot: WidgetStorage.read())], policy: .never))
    }
}

struct ChangePocketPage: AppIntent {
    static var title: LocalizedStringResource = "Show more Pocket apps"
    static var openAppWhenRun = false
    @Parameter(title: "Direction") var direction: Int
    @Parameter(title: "Page size") var size: Int
    init() {}
    init(direction: Int, size: Int) { self.direction = direction; self.size = size }
    func perform() async throws -> some IntentResult {
        let size = size == 8 ? 8 : 4
        let snapshot = WidgetStorage.read()
        let page = snapshot.page(WidgetStorage.page(size: size), size: size)
        let next = (page.index + (direction < 0 ? -1 : 1) + page.count) % page.count
        WidgetStorage.setPage(next, size: size)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
        return .result()
    }
}

struct PocketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PocketEntry
    private let ink = Color(red: 0.15, green: 0.25, blue: 0.20)
    private var size: Int { family == .systemLarge ? 8 : 4 }
    private var page: (apps: [WidgetMiniApp], index: Int, count: Int) {
        entry.snapshot.page(WidgetStorage.page(size: size), size: size)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Link(destination: WidgetStorage.libraryURL) {
                    Label("Pocket", systemImage: "square.grid.2x2.fill")
                        .font(.system(size: 15, weight: .semibold))
                }.accessibilityLabel("Open Pocket Library")
                Spacer()
                if page.count > 1 {
                    Button(intent: ChangePocketPage(direction: -1, size: size)) { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                        .accessibilityLabel("Previous apps")
                    Text("\(page.index + 1)/\(page.count)").font(.caption.monospacedDigit())
                    Button(intent: ChangePocketPage(direction: 1, size: size)) { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                        .accessibilityLabel("Next apps")
                } else {
                    Text("\(entry.snapshot.apps.count) apps").font(.caption).foregroundStyle(ink.opacity(0.65))
                }
            }.buttonStyle(.plain)
            if entry.snapshot.apps.isEmpty {
                Link(destination: WidgetStorage.libraryURL) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.snapshot.account == nil ? "Your apps, right here." : "Room for something good.")
                            .font(.headline)
                        Text(entry.snapshot.account == nil ? "Open Pocket and sign in." : "Add an app or ask a friend to share one.")
                            .font(.caption).foregroundStyle(ink.opacity(0.7))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(page.apps) { app in
                        Link(destination: app.deepLink) {
                            HStack(spacing: 9) {
                                icon(app)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    if family == .systemLarge {
                                        Text(app.shared ? "Shared with you" : "Your app").font(.system(size: 10)).foregroundStyle(ink.opacity(0.6))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9).frame(height: family == .systemLarge ? 52 : 44)
                            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
                        }.accessibilityLabel("Open \(app.name)")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(ink)
        .containerBackground(Color(red: 0.965, green: 0.961, blue: 0.929), for: .widget)
        .widgetURL(WidgetStorage.libraryURL)
    }
    @ViewBuilder private func icon(_ app: WidgetMiniApp) -> some View {
        if let data = app.icon, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(String(app.name.prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(ink.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

@main struct PocketAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStorage.kind, provider: PocketProvider()) { PocketWidgetView(entry: $0) }
            .configurationDisplayName("Pocket apps")
            .description("Your mini apps and apps shared with you. Tap one to open it in Pocket.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
