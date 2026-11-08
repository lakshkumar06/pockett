import SwiftUI
import ImageIO

struct RootView: View {
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var launch: AppLaunch?
    @State private var notice: String?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(open: open) }.tabItem { Label("Home", image: "pocket-grid-2x2") }.tag(0)
            NavigationStack { ActivityView(open: openEvent) }.tabItem { Label("Activity", image: "pocket-inbox") }.badge(backend.unreadCount).tag(1)
            NavigationStack { AccountView() }.tabItem { Label("You", image: "pocket-user-round") }.tag(2)
        }
        .fullScreenCover(item: $launch) { launch in
            HostedAppScreen(launch: launch).environmentObject(backend).environmentObject(home)
        }
        .overlay(alignment: .top) {
            if backend.busy { ProgressView("Opening…").padding(12).background(.regularMaterial, in: Capsule()) }
        }
        .alert("Couldn't complete that", isPresented: Binding(get: { backend.error != nil || notice != nil }, set: { if !$0 { backend.error = nil; notice = nil } })) {
            Button("OK") { backend.error = nil; notice = nil }
        } message: { Text(backend.error ?? notice ?? "Try again.") }
        .onChange(of: tab) { _, _ in PocketHaptics.selection() }
        .sensoryFeedback(.selection, trigger: home.state.pinned)
        .onAppear { handlePending() }
        .onChange(of: backend.pendingURL) { _, _ in handlePending() }
        .onChange(of: backend.busy) { _, busy in if !busy { handlePending() } }
        .task {
            await backend.refreshActivity()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if phase == .active { await backend.refresh() }
            }
        }
    }
    private func open(_ id: String) { PocketHaptics.tap(); Task { launch = await backend.launch(id) } }
    private func openEvent(_ entry: InboxEntry) { PocketHaptics.tap(); Task { launch = await backend.launch(entry.appId, event: entry.eventId) } }
    private func handlePending() {
        guard !backend.busy, let url = backend.pendingURL else { return }
        backend.pendingURL = nil
        guard let route = DeepLink(url: url) else { notice = "This Pocket link is invalid."; return }
        switch route {
        case .library: launch = nil; tab = 0
        case .activity: launch = nil; tab = 1
        case .community: launch = nil; tab = 0; notice = "Community demos have been retired. Your saved apps are still in Pocket."
        case .app(let id):
            if let demo = Catalog.apps.first(where: { $0.id == id }) { launch = AppLaunch(app: demo, exactTarget: nil) }
            else { open(id) }
        case .event(let app, let event): Task { launch = await backend.launch(app, event: event) }
        }
    }
}

struct HostedAppScreen: View {
    let launch: AppLaunch
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var session: WebSession?
    var body: some View {
        Group { if let session { WebViewer(session: session) } else { ProgressView("Opening app…") } }
            .task {
                WebSessionPool.shared.use(identity: backend.identity)
                let value = WebSessionPool.shared.session(app: launch.app, initial: home.lastURL(app: launch.app.id, entry: launch.app.url), exactTarget: launch.exactTarget)
                let identity = backend.identity
                value.onVisit = { url in
                    guard backend.identity == identity else { return }
                    home.remember(url, app: launch.app.id, entry: launch.app.url)
                }
                session = value
            }
            .onChange(of: backend.apps) { _, apps in
                guard !Catalog.apps.contains(where: { $0.id == launch.app.id }) else { return }
                if !apps.contains(where: { $0.id == launch.app.id && $0.url == launch.app.url }) { WebSessionPool.shared.remove(launch.app.id); dismiss() }
            }
    }
}

// Shared native styling keeps forms, the library and viewer in one visual family.
enum PocketStyle {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x203D33, 0xD9EF85)
    static let ink = adaptive(0x203D33, 0xF5F3EB)
    static let canvas = adaptive(0xF3F4F0, 0x101713)
    static let surface = adaptive(0xFFFFFF, 0x263C31)
    static let soft = adaptive(0xE3E8DE, 0x27372D)
    static let hero = adaptive(0x203D33, 0xE8EBDD)
    static let heroInk = adaptive(0xF5F3EB, 0x203D33)
    static let heroAccent = adaptive(0xD9EF85, 0x203D33)
    static let lime = Color(red: 217/255, green: 239/255, blue: 133/255)
    static let forest = Color(red: 32/255, green: 61/255, blue: 51/255)
    static let line = ink.opacity(0.08)
}

// Bundled OFL fonts; every text role scales with the user's Dynamic Type setting.
extension Font {
    static let pocketDisplay = Font.custom("CalSansTextUI-Bold", size: 38, relativeTo: .largeTitle)
    static let pocketTitle = Font.custom("CalSansTextUI-SemiBold", size: 27, relativeTo: .title)
    static let pocketHeadline = Font.custom("CalSansTextUI-SemiBold", size: 18, relativeTo: .headline)
    static let pocketBody = Font.custom("CalSansTextUI-Regular", size: 17, relativeTo: .body)
    static let pocketSubheadline = Font.custom("CalSansTextUI-Regular", size: 15, relativeTo: .subheadline)
    static let pocketCaption = Font.custom("CalSansTextUI-Regular", size: 12, relativeTo: .caption)
}

struct PocketHeading: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(.pocketCaption).tracking(1.1).foregroundStyle(.secondary)
            Text(title).font(.pocketDisplay).tracking(-0.8).foregroundStyle(PocketStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

enum PocketHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

struct PocketPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    func pocketList() -> some View {
        self.scrollContentBackground(.hidden).background(PocketStyle.canvas)
            .font(.pocketBody).tint(PocketStyle.accent)
    }
}

struct AppMark: View {
    let name: String
    var size: CGFloat = 48
    private var hue: Double { Double(name.utf8.reduce(0) { ($0 + Int($1)) % 360 }) / 360 }
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.custom("CalSansTextUI-SemiBold", fixedSize: size * 0.42))
            .foregroundStyle(Color(hue: hue, saturation: 0.4, brightness: 0.35))
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.16, brightness: 0.94), in: RoundedRectangle(cornerRadius: size * 0.27))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(.black.opacity(0.04)))
            .accessibilityHidden(true)
    }
}

struct PocketIcon: View {
    let name: String
    var size: CGFloat = 24
    init(_ name: String, size: CGFloat = 24) { self.name = name; self.size = size }
    var body: some View {
        Image("pocket-" + name).resizable().renderingMode(.template)
            .scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct AppIdentity: View {
    let app: RegisteredApp?
    var size: CGFloat = 48
    @State private var image: UIImage?
    private var symbol: String {
        let name = app?.name.lowercased() ?? ""
        if name.contains("note") { return "notebook-pen" }
        if name.contains("focus") || name.contains("timer") { return "timer" }
        if name.contains("read") || name.contains("book") { return "book-open" }
        if name.contains("calendar") || name.contains("gather") { return "calendar-days" }
        if name.contains("wallet") || name.contains("budget") { return "wallet" }
        return "grid-2x2"
    }
    private var color: Color {
        let palette: [Color] = [PocketStyle.lime, Color(red: 0.73, green: 0.79, blue: 1), Color(red: 1, green: 0.68, blue: 0.46), Color(red: 0.55, green: 0.84, blue: 0.76)]
        let value = (app?.id ?? "").utf8.reduce(0) { ($0 + Int($1)) % palette.count }
        return palette[value]
    }
    var body: some View {
        ZStack {
            color
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { PocketIcon(symbol, size: size * 0.51).foregroundStyle(PocketStyle.forest) }
        }.frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.black.opacity(0.07)))
            .accessibilityHidden(true)
            .task(id: app?.manifest?.iconURL) {
                image = nil
                guard let url = app?.manifest?.iconURL else { return }
                image = await AppIconLoader.load(url)
            }
    }
}

/// Separate ephemeral image transport: no Pocket tokens, cookies or credentials.
private enum AppIconLoader {
    static func load(_ url: URL) async -> UIImage? {
        guard url.scheme == "https", url.user == nil, url.password == nil else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.urlCache = nil; config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", response.expectedContentLength <= 524288,
                  response.mimeType?.hasPrefix("image/") == true else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 524288, !Task.isCancelled else { return nil }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        } catch { return nil }
    }
}

/// Decorative bundled artwork; all meaningful content is live SwiftUI above it.
struct PocketArt: View {
    let name: String
    var body: some View {
        GeometryReader { geometry in
            Image(name).resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct HomeView: View {
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    @EnvironmentObject private var legacy: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    let open: (String) -> Void
    @State private var adding = false
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    private var apps: [RegisteredApp] { backend.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) } }
    private var recent: RegisteredApp? { home.state.recent.compactMap { id in backend.apps.first { $0.id == id && $0.kind != .native } }.first }
    private var featured: RegisteredApp? { recent ?? backend.apps.first { $0.kind != .native } }
    private var pinned: [RegisteredApp] { apps.filter { home.state.pinned.contains($0.id) && $0.kind != .native } }
    private var remaining: [RegisteredApp] { query.isEmpty ? apps.filter { !home.state.pinned.contains($0.id) || $0.kind == .native } : apps }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                VStack(alignment: .leading, spacing: 28) {
                    if query.isEmpty, !pinned.isEmpty {
                        VStack(spacing: 8) {
                            section("Pinned", count: pinned.count)
                            ForEach(pinned) { app in appRow(app) }
                        }
                    }
                    if !remaining.isEmpty || !query.isEmpty {
                        VStack(spacing: 8) {
                            section(query.isEmpty ? (pinned.isEmpty ? "Your apps" : "More apps") : "Results", count: remaining.count)
                            ForEach(remaining) { app in appRow(app) }
                            if remaining.isEmpty {
                                ContentUnavailableView.search(text: query)
                            }
                        }
                    }
                    if backend.apps.isEmpty && query.isEmpty {
                        Text("Save a website you use. It stays here, ready for next time.")
                            .font(.pocketBody).foregroundStyle(.secondary)
                    }
                    if query.isEmpty, !legacy.saved.isEmpty {
                        NavigationLink { LegacyBookmarks() } label: {
                            HStack { Text("Earlier bookmarks"); Spacer(); PocketIcon("arrow-up-right", size: 20) }
                                .font(.pocketSubheadline).padding(.vertical, 12)
                        }
                    }
                }.padding(24)
            }.frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(PocketStyle.canvas).toolbar(.hidden, for: .navigationBar)
            .refreshable { await backend.refresh() }
            .sheet(isPresented: $adding) { AddAppView() }
    }
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("pocket").font(.pocketDisplay).tracking(-1.5).foregroundStyle(.white)
                Spacer()
                Button {
                    searching.toggle(); searchFocused = searching
                    if !searching { query = "" }
                    PocketHaptics.selection()
                } label: {
                    PocketIcon(searching ? "x" : "search", size: 22)
                        .frame(width: 46, height: 46).background(.white.opacity(0.16), in: Circle())
                }.foregroundStyle(.white).accessibilityLabel(searching ? "Close search" : "Search apps")
                Button { adding = true; PocketHaptics.tap() } label: {
                    PocketIcon("plus").frame(width: 46, height: 46)
                        .foregroundStyle(PocketStyle.forest).background(PocketStyle.lime, in: Circle())
                }.accessibilityLabel("Add app")
            }.buttonStyle(PocketPressStyle())
            if searching {
                HStack {
                    PocketIcon("search", size: 20)
                    TextField("Find an app", text: $query).focused($searchFocused).autocorrectionDisabled()
                        .accessibilityLabel("Find an app")
                }.font(.pocketBody).foregroundStyle(PocketStyle.forest).padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            }
            if !searching {
                Spacer(minLength: typeSize.isAccessibilitySize ? 100 : 170)
                Button {
                    if let app = featured { open(app.id) } else { adding = true }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(featured == nil ? "MAKE IT YOURS" : recent == nil ? "OPEN APP" : "CONTINUE")
                            .font(.pocketCaption).tracking(1.4).foregroundStyle(PocketStyle.lime)
                        HStack(alignment: .bottom, spacing: 16) {
                            Text(featured?.name ?? "Your first app.")
                                .font(.pocketDisplay).tracking(-0.8).foregroundStyle(.white)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            PocketIcon(featured == nil ? "plus" : "arrow-up-right", size: 26)
                                .foregroundStyle(PocketStyle.forest).frame(width: 50, height: 50)
                                .background(PocketStyle.lime, in: Circle())
                        }
                        if let app = featured {
                            Text(app.url?.host ?? "Web app").font(.pocketCaption).foregroundStyle(.white.opacity(0.8))
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(PocketPressStyle())
            }
        }.padding(24).frame(maxWidth: .infinity, minHeight: searching ? 140 : 410, alignment: .topLeading)
            .background {
                ZStack {
                    PocketArt(name: "pocket-folded-world")
                    LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .clear, location: 0.4), .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom)
                }
            }.clipped()
    }
    private func section(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.pocketTitle).foregroundStyle(PocketStyle.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(String(format: "%02d", count)).font(.pocketCaption).monospacedDigit().foregroundStyle(.secondary)
        }.padding(.bottom, 8)
    }
    private func appRow(_ app: RegisteredApp) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { open(app.id) } label: {
                    HStack(spacing: 16) {
                        AppIdentity(app: app, size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.pocketHeadline).foregroundStyle(PocketStyle.ink)
                            Text(app.kind == .native ? "Older app · unsupported" : app.owner == backend.username ? (app.url?.host ?? "Your app") : "Shared by \(app.owner)")
                                .font(.pocketCaption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(PocketPressStyle())
                NavigationLink { RegisteredAppDetail(id: app.id, open: open) } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("\(app.name) settings and sharing")
            }.padding(.vertical, 12)
            Divider().padding(.leading, 74)
        }.contextMenu {
            if app.kind != .native { Button(home.state.pinned.contains(app.id) ? "Unpin" : "Pin", systemImage: "pin") { home.pin(app.id) } }
            NavigationLink { RegisteredAppDetail(id: app.id, open: open) } label: { Label("App settings", systemImage: "slider.horizontal.3") }
        }
    }
}

struct LegacyBookmarks: View {
    @EnvironmentObject private var store: Store
    @State private var launch: AppLaunch?
    var body: some View {
        List {
            ForEach(Catalog.apps.filter { store.saved.contains($0.id) }) { app in
                Button(app.name) { launch = AppLaunch(app: app, exactTarget: nil) }
                    .swipeActions { Button("Remove", role: .destructive) { store.toggleSaved(app.id) } }
            }
        }.navigationTitle("Earlier bookmarks")
            .fullScreenCover(item: $launch) { HostedAppScreen(launch: $0) }
    }
}

struct ActivityView: View {
    @EnvironmentObject private var backend: Backend
    let open: (InboxEntry) -> Void
    @State private var appFilter = ""
    @State private var unreadOnly = false
    private var entries: [InboxEntry] { backend.inbox.filter { (appFilter.isEmpty || $0.appId == appFilter) && (!unreadOnly || !$0.read) } }
    var body: some View {
        List {
            PocketHeading(eyebrow: "\(backend.unreadCount) unread", title: "Activity")
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 20, trailing: 4))
            Section {
                HStack {
                    Picker("App", selection: $appFilter) {
                        Text("All apps").tag("")
                        ForEach(backend.apps.filter { $0.kind != .native }) { Text($0.name).tag($0.id) }
                    }.labelsHidden().pickerStyle(.menu)
                    Spacer()
                    Toggle("Unread", isOn: $unreadOnly).toggleStyle(.button).buttonStyle(.bordered)
                }
            }.listRowBackground(Color.clear)
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    PocketArt(name: "pocket-quiet-fold").frame(height: 220).clipped()
                    Text("All caught up.").font(.pocketTitle)
                    Text("Updates from connected apps arrive here.").font(.pocketBody).foregroundStyle(.secondary)
                    NavigationLink("Manage app updates") { NotificationSettings() }.font(.pocketHeadline)
                }.padding(.bottom, 16).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(entries) { item in
                Button { open(item) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        AppIdentity(app: backend.apps.first { $0.id == item.appId }, size: 40)
                            .overlay(alignment: .topTrailing) {
                                if !item.read { Circle().fill(PocketStyle.accent).frame(width: 9, height: 9).overlay(Circle().stroke(PocketStyle.surface, lineWidth: 2)) }
                            }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(backend.apps.first { $0.id == item.appId }?.name ?? "App").font(.caption.weight(.semibold)).foregroundStyle(PocketStyle.accent)
                                Spacer()
                                Text(Date(timeIntervalSince1970: item.createdAt), style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(item.title).font(.pocketHeadline).foregroundStyle(.primary)
                            Text(item.body).font(.pocketSubheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(PocketPressStyle()).listRowBackground(PocketStyle.surface)
                    .accessibilityLabel("\(item.read ? "Read" : "Unread"), \(item.title), \(item.body)")
            }
            if backend.nextCursor != nil { Button("Load earlier updates") { Task { await backend.refreshActivity(more: true, appId: appFilter.isEmpty ? nil : appFilter) } } }
            Section {
                NavigationLink("Notification settings") { NotificationSettings() }
            } footer: {
                Text(backend.deliveryMode == "local" ? "Local test mode · updates appear when Pocket refreshes. Push delivery is not enabled." : "Activity is saved here even when device notifications are off.")
            }
        }.pocketList().navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
            .listSectionSpacing(16)
            .sensoryFeedback(.selection, trigger: unreadOnly)
            .refreshable { await backend.refreshActivity(appId: appFilter.isEmpty ? nil : appFilter) }
            .onChange(of: appFilter) { _, value in Task { await backend.refreshActivity(appId: value.isEmpty ? nil : value, setFilter: true) } }
    }
}

struct NotificationSettings: View {
    @EnvironmentObject private var backend: Backend
    @State private var disconnecting: NotificationSubscription?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PocketHeading(eyebrow: "You're in control", title: "App updates")
                Text("Choose which apps can reach your inbox.").font(.pocketBody).foregroundStyle(.secondary)
                if backend.subscriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        PocketIcon("bell", size: 44).foregroundStyle(PocketStyle.accent)
                        Text("Connect your first app").font(.pocketTitle)
                        Text("Open an app's settings from Home and choose Connect updates. You decide what gets through.")
                            .font(.pocketBody).foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                }
                ForEach(backend.subscriptions) { sub in
                    let app = backend.apps.first { $0.id == sub.appId }
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            AppIdentity(app: app, size: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app?.name ?? "App").font(.pocketHeadline)
                                Text(sub.notificationsEnabled ? "Updates on" : "Muted")
                                    .font(.pocketCaption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        Toggle("Allow updates", isOn: Binding(get: { sub.notificationsEnabled }, set: { enabled in
                            PocketHaptics.selection()
                            Task { await backend.notificationPreference(sub, enabled: enabled) }
                        })).font(.pocketBody)
                        Divider()
                        Button("Disconnect app", role: .destructive) { disconnecting = sub }
                            .font(.pocketSubheadline).frame(minHeight: 44)
                    }.padding(20).background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                }
                Label(backend.deliveryMode == "local" ? "Local test mode. Updates refresh while Pocket is open." : "Inbox updates stay available even when device notifications are off.", systemImage: "info.circle")
                    .font(.pocketCaption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline).disabled(backend.busy)
            .confirmationDialog("Disconnect this app?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
                if let sub = disconnecting {
                    Button("Disconnect", role: .destructive) { Task { await backend.disconnect(sub); disconnecting = nil } }
                }
                Button("Cancel", role: .cancel) { disconnecting = nil }
            } message: { Text("To receive new updates, you'll need to connect the app again.") }
    }
}

struct RegisteredAppDetail: View {
    let id: String
    let open: (String) -> Void
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    @State private var recipient = ""
    @State private var consenting = false
    @State private var pairing: PairingReply?
    @State private var pairingBusy = false
    private var app: RegisteredApp? { backend.apps.first { $0.id == id } }
    var body: some View {
        Group {
            if let app {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            AppIdentity(app: app, size: 80)
                            Text(app.name).font(.pocketTitle).foregroundStyle(PocketStyle.ink)
                            Text(app.summary).font(.pocketBody).foregroundStyle(.secondary)
                            if app.kind == .native { Text("This older native experience is unsupported. Its stored records remain intact.") }
                            else {
                                Button("Open app", systemImage: "arrow.up.right") { open(id) }.buttonStyle(.borderedProminent)
                                Button(home.state.pinned.contains(id) ? "Unpin from Home" : "Pin to Home", systemImage: "pin") { home.pin(id) }
                            }
                        }.padding(.vertical, 8)
                        ShareLink(item: app.miniApp.deepLink) { Label("Share Pocket link", systemImage: "square.and.arrow.up") }
                    }
                    if app.manifest != nil {
                        Section("Updates from this app") {
                            if let sub = backend.subscriptions.first(where: { $0.appId == id }) {
                                Toggle("Allow updates", isOn: Binding(get: { sub.notificationsEnabled }, set: { value in Task { await backend.notificationPreference(sub, enabled: value) } }))
                                Button("Disconnect", role: .destructive) { Task { await backend.disconnect(sub); pairing = nil } }
                            } else {
                                Button("Connect updates", systemImage: "bell.badge") { consenting = true }.disabled(pairingBusy)
                            }
                            if let pairing {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    if context.date.timeIntervalSince1970 < pairing.expiresAt {
                                        Text("Paste this one-use code into the app's notification connection screen. It expires in five minutes.").font(.pocketCaption)
                                        Text(pairing.pairingCode).font(.caption.monospaced()).textSelection(.enabled)
                                        Button("Copy pairing code") {
                                            UIPasteboard.general.setItems([["public.utf8-plain-text": pairing.pairingCode]], options: [.localOnly: true, .expirationDate: Date(timeIntervalSince1970: pairing.expiresAt)])
                                        }
                                    } else { Text("Code expired. Connect again to get a new code.").font(.pocketCaption) }
                                }
                            }
                        }
                    }
                    if app.owner == backend.username {
                        Section {
                            TextField("Their Pocket username", text: $recipient).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Grant access") { Task { if await backend.share(app, with: recipient) { recipient = "" } } }.disabled(recipient.isEmpty)
                            ForEach(app.sharedWith, id: \.self) { user in
                                HStack { Text(user); Spacer(); Button("Revoke", role: .destructive) { Task { await backend.revoke(app, recipient: user) } } }
                            }
                        } header: { Text("Share access") } footer: { Text("Sharing gives access to this Pocket listing. The website manages its own accounts and data.") }
                    }
                    if let url = app.url { Section("Website") { Text(url.host ?? url.absoluteString).foregroundStyle(.secondary) } }
                }.pocketList().navigationTitle(app.name).navigationBarTitleDisplayMode(.inline)
                    .confirmationDialog("Allow updates from \(app.name)?", isPresented: $consenting, titleVisibility: .visible) {
                        Button("Allow and create pairing code") {
                            Task {
                                pairingBusy = true; defer { pairingBusy = false }
                                do { pairing = try await backend.pairing(appId: id) }
                                catch { if !isRequestCancellation(error) { backend.error = error.localizedDescription } }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: { Text("\(app.url?.host ?? "This website") will be able to send updates to your Pocket inbox once you enter the code on its website. You can mute or disconnect it at any time. This does not enable device notifications.") }
            } else { ContentUnavailableView("App unavailable", systemImage: "lock", description: Text("This listing was removed or access was revoked.")) }
        }.disabled(backend.busy).refreshable { await backend.refresh() }
    }
}

struct AccountView: View {
    @EnvironmentObject private var backend: Backend
    var body: some View {
        if let username = backend.username { ProfileScreen(username: username) }
        else { AccountForm() }
    }
}

private struct ProfileScreen: View {
    let username: String
    @EnvironmentObject private var backend: Backend
    @ObservedObject private var notifications = PocketNotifications.shared
    @State private var serverSheet = false
    @State private var widgetSheet = false
    @State private var signingOut = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PocketHeading(eyebrow: "Your space", title: "You")
                VStack(alignment: .leading, spacing: 20) {
                    PocketArt(name: "pocket-quiet-fold").frame(height: 200).clipped()
                        .padding(.horizontal, -24)
                    HStack(alignment: .center, spacing: 16) {
                        Text(String(username.prefix(2)).uppercased()).font(.pocketHeadline)
                            .foregroundStyle(PocketStyle.forest).frame(width: 54, height: 54)
                            .background(PocketStyle.lime, in: Circle())
                        Text("@" + username).font(.pocketTitle).foregroundStyle(PocketStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 28) {
                        stat(backend.apps.filter { $0.owner == username }.count, "Your apps")
                        stat(backend.apps.filter { $0.owner != username }.count, "Shared with you")
                    }
                    Divider()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Stay connected").font(.pocketHeadline)
                    NavigationLink { NotificationSettings() } label: {
                        setting("bell", "App updates", "\(backend.subscriptions.count) connected apps", accent: PocketStyle.lime)
                    }.buttonStyle(PocketPressStyle())
                    Button { Task { await notifications.requestPermission() } } label: {
                        setting("inbox", "Device notifications", notifications.status, accent: Color(red: 0.73, green: 0.79, blue: 1))
                    }.buttonStyle(PocketPressStyle())
                }
                Button { widgetSheet = true; PocketHaptics.tap() } label: {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            PocketIcon("grid-2x2", size: 30)
                            Spacer()
                            PocketIcon("arrow-up-right")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("One tap away.").font(.pocketTitle)
                            Text("Put your apps on your Home Screen.").font(.pocketSubheadline)
                        }
                        HStack(spacing: 10) {
                            ForEach(Array(backend.apps.filter { $0.kind != .native }.prefix(4))) { app in
                                AppIdentity(app: app, size: 44)
                            }
                            if backend.apps.isEmpty { Text("Pocket library widget").font(.pocketCaption) }
                        }
                    }.foregroundStyle(PocketStyle.forest).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PocketStyle.lime, in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(PocketPressStyle())
                VStack(spacing: 0) {
                    Button { serverSheet = true } label: {
                        setting("link", "Connection", URL(string: backend.address)?.host ?? "Pocket server", accent: PocketStyle.soft)
                    }.buttonStyle(PocketPressStyle())
                    Divider().padding(.horizontal, 20)
                    Button { signingOut = true } label: {
                        HStack {
                            Text("Sign out").font(.pocketHeadline)
                            Spacer()
                            PocketIcon("arrow-up-right", size: 20)
                        }.foregroundStyle(.red).padding(20).frame(minHeight: 60)
                    }.buttonStyle(PocketPressStyle())
                }.background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                Text("POCKET / YOUR APPS, TOGETHER").font(.pocketCaption).tracking(1.2).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $serverSheet) { ConnectionSettings() }
            .sheet(isPresented: $widgetSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            PocketIcon("grid-2x2", size: 56).foregroundStyle(PocketStyle.accent)
                            PocketHeading(eyebrow: "Pocket widget", title: "Closer to your apps.")
                            Text("Touch and hold your iPhone Home Screen. Tap Edit, then Add Widget. Search for Pocket and choose your layout.")
                            Text("Your saved and shared apps appear in the widget. Refresh Home in Pocket to update the list.").foregroundStyle(.secondary)
                        }.padding(24)
                    }.background(PocketStyle.canvas).font(.pocketBody)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { widgetSheet = false } } }
                }.presentationDetents([.medium, .large])
            }
            .confirmationDialog("Sign out of Pocket?", isPresented: $signingOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await backend.logout() } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Open website sessions will close. Your saved apps stay in your account.") }
    }
    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.pocketTitle).monospacedDigit()
            Text(label).font(.pocketCaption)
        }.foregroundStyle(PocketStyle.ink).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func setting(_ icon: String, _ title: String, _ detail: String, accent: Color) -> some View {
        HStack(spacing: 16) {
            PocketIcon(icon, size: 23).foregroundStyle(PocketStyle.forest)
                .frame(width: 48, height: 48).background(accent, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.pocketHeadline).foregroundStyle(PocketStyle.ink)
                Text(detail).font(.pocketCaption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            PocketIcon("chevron-right", size: 18).foregroundStyle(.secondary)
        }.padding(18).background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct ConnectionSettings: View {
    @EnvironmentObject private var backend: Backend
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PocketHeading(eyebrow: "Connection", title: "Your Pocket server")
                    TextField("Server address", text: $address).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(18).background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityLabel("Server address")
                    Text("Use the same address on your devices. Changing servers signs you out.").foregroundStyle(.secondary)
                    Button {
                        backend.changeServer(address); dismiss()
                    } label: {
                        Text("Use this server").font(.pocketHeadline).frame(maxWidth: .infinity).padding(18)
                            .foregroundStyle(PocketStyle.heroInk).background(PocketStyle.hero, in: Capsule())
                    }.buttonStyle(PocketPressStyle()).disabled(address.isEmpty || address == backend.address)
                }.padding(24)
            }.background(PocketStyle.canvas).font(.pocketBody)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onAppear { address = backend.address }
    }
}
