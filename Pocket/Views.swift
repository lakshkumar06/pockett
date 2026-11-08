import SwiftUI
import ImageIO

struct RootView: View {
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    @Environment(\.scenePhase) private var phase
    @AppStorage("pocket.onboarding.dark.v1") private var completedOnboarding = false
    @State private var tab = 0
    @State private var launch: AppLaunch?
    @State private var notice: String?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(open: open) }
                .tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { SearchView(open: open) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { ActivityView(open: openEvent) }
                .tabItem { Label("Activity", systemImage: "clock") }.badge(backend.unreadCount).tag(2)
            NavigationStack { AccountView() }
                .tabItem { Label("You", systemImage: "person") }.tag(3)
        }
        .tint(PocketStyle.accent)
        .toolbarBackground(PocketStyle.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(item: $launch) { launch in
            HostedAppScreen(launch: launch).environmentObject(backend).environmentObject(home)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !completedOnboarding },
            set: { if !$0 { completedOnboarding = true } }
        )) { OnboardingView { completedOnboarding = true } }
        .overlay(alignment: .top) {
            if backend.busy {
                ProgressView("Working…")
                    .font(.pocketCaption).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(PocketStyle.elevated, in: Capsule())
                    .overlay(Capsule().stroke(PocketStyle.line))
                    .padding(.top, 8)
            }
        }
        .alert("Couldn’t complete that", isPresented: Binding(
            get: { backend.error != nil || notice != nil },
            set: { if !$0 { backend.error = nil; notice = nil } }
        )) {
            Button("OK") { backend.error = nil; notice = nil }
        } message: { Text(backend.error ?? notice ?? "Try again.") }
        .onChange(of: tab) { _, _ in PocketHaptics.selection() }
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

    private func open(_ id: String) {
        PocketHaptics.tap()
        if let app = Catalog.apps.first(where: { $0.id == id }) {
            home.opened(id)
            launch = AppLaunch(app: app, exactTarget: nil)
        } else {
            Task { launch = await backend.launch(id) }
        }
    }

    private func openEvent(_ entry: InboxEntry) {
        PocketHaptics.tap()
        Task { launch = await backend.launch(entry.appId, event: entry.eventId) }
    }

    private func handlePending() {
        guard !backend.busy, let url = backend.pendingURL else { return }
        backend.pendingURL = nil
        guard let route = DeepLink(url: url) else { notice = "This Pocket link is invalid."; return }
        switch route {
        case .library: launch = nil; tab = 0
        case .activity: launch = nil; tab = 2
        case .community: launch = nil; tab = 0; notice = "Communities are no longer available. Your apps are still here."
        case .app(let id): open(id)
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
        Group {
            if let session { WebViewer(session: session) }
            else { ProgressView("Opening app…").frame(maxWidth: .infinity, maxHeight: .infinity).background(PocketStyle.canvas) }
        }
        .task {
            WebSessionPool.shared.use(identity: backend.identity)
            let value = WebSessionPool.shared.session(
                app: launch.app,
                initial: home.lastURL(app: launch.app.id, entry: launch.app.url),
                exactTarget: launch.exactTarget
            )
            let identity = backend.identity
            value.onVisit = { url in
                guard backend.identity == identity else { return }
                home.remember(url, app: launch.app.id, entry: launch.app.url)
            }
            session = value
        }
        .onChange(of: backend.apps) { _, apps in
            guard !Catalog.apps.contains(where: { $0.id == launch.app.id }) else { return }
            if !apps.contains(where: { $0.id == launch.app.id && $0.url == launch.app.url }) {
                WebSessionPool.shared.remove(launch.app.id)
                dismiss()
            }
        }
    }
}

enum PocketStyle {
    static let accent = Color(red: 1, green: 0.35, blue: 0.08)
    static let accentPressed = Color(red: 0.88, green: 0.25, blue: 0.04)
    static let ink = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let secondaryInk = Color(red: 0.68, green: 0.68, blue: 0.72)
    static let canvas = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let surface = Color(red: 0.09, green: 0.09, blue: 0.105)
    static let elevated = Color(red: 0.125, green: 0.125, blue: 0.145)
    static let soft = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let line = Color.white.opacity(0.12)
    static let danger = Color(red: 1, green: 0.32, blue: 0.32)
    static let cardRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 12
}

extension Font {
    static let pocketDisplay = Font.custom("CalSansTextUI-SemiBold", size: 28, relativeTo: .largeTitle)
    static let pocketTitle = Font.custom("CalSansTextUI-SemiBold", size: 20, relativeTo: .title2)
    static let pocketHeadline = Font.custom("CalSansTextUI-SemiBold", size: 16, relativeTo: .headline)
    static let pocketBody = Font.custom("CalSansTextUI-Regular", size: 16, relativeTo: .body)
    static let pocketSubheadline = Font.custom("CalSansTextUI-Regular", size: 13, relativeTo: .subheadline)
    static let pocketCaption = Font.custom("CalSansTextUI-Regular", size: 13, relativeTo: .caption)
}

struct PocketHeading: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: eyebrow.isEmpty ? 0 : 6) {
            if !eyebrow.isEmpty { Text(eyebrow).font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk) }
            Text(title).font(.pocketDisplay).foregroundStyle(PocketStyle.ink)
        }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

enum PocketHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

struct PocketPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.74 : 1) : 0.45)
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isEnabled)
    }
}

extension View {
    func pocketList() -> some View {
        scrollContentBackground(.hidden)
            .background(PocketStyle.canvas)
            .font(.pocketBody)
            .tint(PocketStyle.accent)
            .foregroundStyle(PocketStyle.ink)
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

struct FaviconMark: View {
    let name: String
    let url: URL?
    var explicitIconURL: URL?
    var size: CGFloat = 48
    @State private var image: UIImage?

    private var faviconURL: URL? {
        if let explicitIconURL { return explicitIconURL }
        guard let url, url.scheme?.lowercased() == "https", let host = url.host else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = host; parts.path = "/favicon.ico"
        return parts.url
    }
    private var hue: Double { Double(name.utf8.reduce(0) { ($0 + Int($1)) % 360 }) / 360 }

    var body: some View {
        ZStack {
            Color(hue: hue, saturation: 0.36, brightness: 0.27)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().padding(size * 0.12)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.custom("CalSansTextUI-SemiBold", fixedSize: size * 0.4))
                    .foregroundStyle(Color(hue: hue, saturation: 0.35, brightness: 0.94))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: min(14, size * 0.27)))
        .overlay(RoundedRectangle(cornerRadius: min(14, size * 0.27)).stroke(PocketStyle.line))
        .accessibilityHidden(true)
        .task(id: faviconURL) {
            image = nil
            guard let faviconURL else { return }
            image = await AppIconLoader.load(faviconURL)
        }
    }
}

struct AppMark: View {
    let name: String
    var size: CGFloat = 48
    var body: some View { FaviconMark(name: name, url: nil, explicitIconURL: nil, size: size) }
}

struct AppIdentity: View {
    let app: RegisteredApp?
    var size: CGFloat = 48
    @State private var customImage: UIImage?
    private let allowedIcons = Set(["check", "notebook-pen", "calendar-days", "wallet", "timer", "book-open", "user-round", "grid-2x2", "inbox", "bell"])

    private var generatedIcon: String? {
        guard let icon = app?.spec?.appearance?.icon, allowedIcons.contains(icon) else { return nil }
        return icon
    }

    private var generatedColor: Color {
        switch app?.spec?.appearance?.theme {
        case "forest": return Color(red: 0.28, green: 0.64, blue: 0.41)
        case "ember": return PocketStyle.accent
        case "ocean": return Color(red: 0.20, green: 0.58, blue: 0.78)
        case "violet": return Color(red: 0.49, green: 0.37, blue: 0.76)
        case "paper": return Color(red: 0.38, green: 0.40, blue: 0.36)
        default: return PocketStyle.elevated
        }
    }

    var body: some View {
        Group {
            if let customImage {
                Image(uiImage: customImage).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: min(14, size * 0.27)))
                    .overlay(RoundedRectangle(cornerRadius: min(14, size * 0.27)).stroke(PocketStyle.line))
                    .accessibilityHidden(true)
            } else if let generatedIcon {
                ZStack {
                    generatedColor
                    PocketIcon(generatedIcon, size: size * 0.5).foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: min(14, size * 0.27)))
                .overlay(RoundedRectangle(cornerRadius: min(14, size * 0.27)).stroke(PocketStyle.line))
                .accessibilityHidden(true)
            } else {
                FaviconMark(name: app?.name ?? "App", url: app?.url, explicitIconURL: app?.manifest?.iconURL, size: size)
            }
        }
        .task(id: app?.id) {
            customImage = app.flatMap { CustomAppIconStore.load($0.id) }
        }
    }
}

enum CustomAppIconStore {
    private static var directory: URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return root.appendingPathComponent("AppIcons", isDirectory: true)
    }

    static func prepare(_ data: Data) -> Data? {
        guard data.count <= 12_000_000, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * 256 / side, y: -crop.minY * 256 / side, width: image.size.width * 256 / side, height: image.size.height * 256 / side))
        }
        if let png = rendered.pngData(), png.count <= 1_000_000 { return png }
        return rendered.jpegData(compressionQuality: 0.86)
    }

    static func save(_ data: Data, for id: String) {
        guard let directory, id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try? data.write(to: directory.appendingPathComponent(id + ".image"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(_ id: String) -> UIImage? {
        guard let directory else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(id + ".image").path)
    }

    static func remove(_ id: String) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".image"))
    }
}

private enum AppIconLoader {
    static func load(_ url: URL) async -> UIImage? {
        guard url.scheme == "https", url.user == nil, url.password == nil else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", response.expectedContentLength <= 524_288,
                  response.mimeType?.hasPrefix("image/") == true else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 524_288, !Task.isCancelled else { return nil }
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

struct HomeView: View {
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    let open: (String) -> Void
    @State private var adding = false
    @State private var importing = false
    @State private var query = ""
    @State private var deleting: RegisteredApp?
    @State private var toast: String?

    private var filteredApps: [RegisteredApp] {
        backend.apps.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
            $0.summary.localizedCaseInsensitiveContains(query) ||
            ($0.url?.host?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    private var recent: [MiniApp] {
        home.state.recent.compactMap { id in
            backend.apps.first(where: { $0.id == id && $0.kind != .native })?.miniApp ?? Catalog.apps.first(where: { $0.id == id })
        }.prefix(6).map { $0 }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .center) {
                    Text("Your apps").font(.pocketDisplay).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { adding = true; PocketHaptics.tap() } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold))
                            .frame(width: 42, height: 42).background(PocketStyle.accent, in: Circle()).foregroundStyle(.white)
                    }.buttonStyle(PocketPressStyle()).accessibilityLabel("Add app")
                }
                SearchField(text: $query, placeholder: "Search your apps")
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

            if !recent.isEmpty && query.isEmpty {
                Section("Recently opened") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recent) { app in
                                Button { open(app.id) } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        recentIcon(app)
                                        Text(app.name).font(.pocketHeadline).lineLimit(1)
                                        Text(app.url.host ?? app.url.absoluteString).font(.pocketCaption)
                                            .foregroundStyle(PocketStyle.secondaryInk).lineLimit(1)
                                    }
                                    .padding(14).frame(width: 148, alignment: .leading)
                                    .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.cardRadius))
                                    .overlay(RoundedRectangle(cornerRadius: PocketStyle.cardRadius).stroke(PocketStyle.line))
                                }.buttonStyle(PocketPressStyle())
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 14, trailing: 0))
            }

            if query.isEmpty {
                Section("Quick actions") {
                    HStack(spacing: 10) {
                        QuickAction(title: "Add app", symbol: "plus") { adding = true }
                        QuickAction(title: "Import", symbol: "square.and.arrow.down") { importing = true }
                        ShareLink(item: URL(string: "pocket://library")!) {
                            QuickActionLabel(title: "Share", symbol: "square.and.arrow.up")
                        }.buttonStyle(PocketPressStyle())
                    }
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 14, trailing: 20))
            }

            Section(query.isEmpty ? "Saved places" : "Results") {
                if backend.busy && backend.apps.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in SkeletonAppRow() }
                } else if filteredApps.isEmpty {
                    EmptyAppsView(searching: !query.isEmpty) { adding = true }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(filteredApps) { app in appRow(app) }
                }
            }
        }
        .listStyle(.plain).pocketList().toolbar(.hidden, for: .navigationBar)
        .refreshable { await backend.refresh() }
        .sheet(isPresented: $adding) { AddAppView(importMode: false) { showToast("App added") } }
        .sheet(isPresented: $importing) { AddAppView(importMode: true) { showToast("App imported") } }
        .confirmationDialog("Delete \(deleting?.name ?? "this app")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            if let deleting {
                Button("Delete app", role: .destructive) {
                    Task {
                        if await backend.delete(deleting) { showToast("App deleted") }
                        self.deleting = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the Pocket listing and its shared access.") }
        .overlay(alignment: .bottom) {
            if let toast { ToastView(message: toast).padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
    }

    private func appRow(_ app: RegisteredApp) -> some View {
        HStack(spacing: 14) {
            Button { open(app.id) } label: {
                HStack(spacing: 14) {
                    AppIdentity(app: app, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.pocketHeadline).foregroundStyle(PocketStyle.ink)
                        HStack(spacing: 5) {
                            Text(app.url?.host ?? (app.kind == .native ? "Unsupported app" : "Web app"))
                            if let opened = home.state.lastOpened[app.id] {
                                Text("·"); Text(opened, style: .relative)
                            }
                        }.font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(PocketPressStyle())
            NavigationLink { RegisteredAppDetail(id: app.id, open: open) } label: {
                Image(systemName: "ellipsis").frame(width: 42, height: 42).foregroundStyle(PocketStyle.secondaryInk)
            }.accessibilityLabel("Details for \(app.name)")
        }
        .padding(.vertical, 7)
        .listRowBackground(PocketStyle.canvas).listRowSeparatorTint(PocketStyle.line)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if app.kind != .native {
                Button(home.state.pinned.contains(app.id) ? "Unpin" : "Pin", systemImage: "pin") { home.pin(app.id) }
                    .tint(PocketStyle.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if app.owner == backend.username {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = app }
            }
            ShareLink(item: app.miniApp.deepLink) { Label("Share", systemImage: "square.and.arrow.up") }.tint(.blue)
        }
        .contextMenu {
            if app.kind != .native { Button(home.state.pinned.contains(app.id) ? "Unpin" : "Pin", systemImage: "pin") { home.pin(app.id) } }
            ShareLink(item: app.miniApp.deepLink) { Label("Share", systemImage: "square.and.arrow.up") }
            if app.owner == backend.username { Button("Delete", systemImage: "trash", role: .destructive) { deleting = app } }
        }
    }

    @ViewBuilder private func recentIcon(_ app: MiniApp) -> some View {
        if let registered = backend.apps.first(where: { $0.id == app.id }) {
            AppIdentity(app: registered, size: 44)
        } else {
            FaviconMark(name: app.name, url: app.url, explicitIconURL: nil, size: 44)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation(.easeIn(duration: 0.2)) { if toast == message { toast = nil } } }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var backend: Backend
    let open: (String) -> Void
    @State private var query = ""

    private var catalog: [MiniApp] {
        Catalog.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
    }
    private var owned: [RegisteredApp] {
        guard !query.isEmpty else { return [] }
        return backend.apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                Text("Search").font(.pocketDisplay).accessibilityAddTraits(.isHeader)
                SearchField(text: $query, placeholder: "Apps, tools, websites")
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 10, trailing: 20))

            if !owned.isEmpty {
                Section("Your apps") {
                    ForEach(owned) { app in
                        NavigationLink { RegisteredAppDetail(id: app.id, open: open) } label: {
                            AppListLabel(name: app.name, detail: app.url?.host ?? "Web app") {
                                AppIdentity(app: app, size: 48)
                            }
                        }
                    }
                }
            }

            Section(query.isEmpty ? "Starter apps" : "Web apps") {
                if catalog.isEmpty && owned.isEmpty {
                    ContentUnavailableView("No apps found", systemImage: "magnifyingglass")
                        .listRowBackground(Color.clear)
                }
                ForEach(catalog) { app in
                    NavigationLink { CatalogAppDetail(app: app, open: open) } label: {
                        AppListLabel(name: app.name, detail: app.url.host ?? app.summary) {
                            FaviconMark(name: app.name, url: app.url, explicitIconURL: nil, size: 48)
                        }
                    }
                }
            }
        }
        .listStyle(.plain).pocketList().toolbar(.hidden, for: .navigationBar)
    }
}

private struct CatalogAppDetail: View {
    let app: MiniApp
    let open: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FaviconMark(name: app.name, url: app.url, explicitIconURL: nil, size: 76)
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.name).font(.pocketDisplay)
                    Text(app.url.host ?? app.url.absoluteString).font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                    Text(app.summary).font(.pocketBody).foregroundStyle(PocketStyle.secondaryInk).padding(.top, 4)
                }
                Button { open(app.id) } label: { PrimaryButtonLabel(title: "Open app", symbol: "arrow.up.right") }
                    .buttonStyle(PocketPressStyle())
                ShareLink(item: app.deepLink) { Label("Share Pocket link", systemImage: "square.and.arrow.up") }
                    .font(.pocketHeadline)
                Text("This is a public third-party website. Pocket does not operate or endorse it.")
                    .font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
            }.padding(20).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
        .navigationTitle("App details").navigationBarTitleDisplayMode(.inline)
    }
}

struct ActivityView: View {
    @EnvironmentObject private var backend: Backend
    let open: (InboxEntry) -> Void
    @State private var appFilter = ""
    @State private var unreadOnly = false
    private var entries: [InboxEntry] {
        backend.inbox.filter { (appFilter.isEmpty || $0.appId == appFilter) && (!unreadOnly || !$0.read) }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Activity").font(.pocketDisplay).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if backend.unreadCount > 0 { Text("\(backend.unreadCount) unread").font(.pocketCaption).foregroundStyle(PocketStyle.accent) }
                }
                HStack {
                    Picker("App", selection: $appFilter) {
                        Text("All apps").tag("")
                        ForEach(backend.apps.filter { $0.kind != .native }) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu)
                    Spacer()
                    Toggle("Unread", isOn: $unreadOnly).toggleStyle(.button).buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 12, trailing: 20))

            if entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(PocketStyle.accent)
                        Text("No new activity").font(.pocketTitle)
                        NavigationLink("Manage app updates") { NotificationSettings() }.font(.pocketHeadline)
                    }.padding(.vertical, 16)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            ForEach(entries) { item in
                Button { open(item) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        AppIdentity(app: backend.apps.first { $0.id == item.appId }, size: 44)
                            .overlay(alignment: .topTrailing) {
                                if !item.read { Circle().fill(PocketStyle.accent).frame(width: 9, height: 9).overlay(Circle().stroke(PocketStyle.canvas, lineWidth: 2)) }
                            }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(backend.apps.first { $0.id == item.appId }?.name ?? "App").font(.pocketCaption).foregroundStyle(PocketStyle.accent)
                                Spacer()
                                Text(Date(timeIntervalSince1970: item.createdAt), style: .relative).font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                            }
                            Text(item.title).font(.pocketHeadline).foregroundStyle(PocketStyle.ink)
                            Text(item.body).font(.pocketSubheadline).foregroundStyle(PocketStyle.secondaryInk).lineLimit(3)
                        }
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(PocketPressStyle()).listRowBackground(PocketStyle.canvas).listRowSeparatorTint(PocketStyle.line)
                .accessibilityLabel("\(item.read ? "Read" : "Unread"), \(item.title), \(item.body)")
            }

            if backend.nextCursor != nil {
                Button("Load earlier updates") { Task { await backend.refreshActivity(more: true, appId: appFilter.isEmpty ? nil : appFilter) } }
            }
        }
        .listStyle(.plain).pocketList().toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: unreadOnly)
        .refreshable { await backend.refreshActivity(appId: appFilter.isEmpty ? nil : appFilter) }
        .onChange(of: appFilter) { _, value in Task { await backend.refreshActivity(appId: value.isEmpty ? nil : value, setFilter: true) } }
    }
}

struct NotificationSettings: View {
    @EnvironmentObject private var backend: Backend
    @State private var disconnecting: NotificationSubscription?
    var body: some View {
        List {
            if backend.subscriptions.isEmpty {
                ContentUnavailableView("No connected apps", systemImage: "bell.slash")
                    .listRowBackground(Color.clear)
            }
            ForEach(backend.subscriptions) { sub in
                let app = backend.apps.first { $0.id == sub.appId }
                Section {
                    HStack(spacing: 12) {
                        AppIdentity(app: app, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app?.name ?? "App").font(.pocketHeadline)
                            Text(sub.notificationsEnabled ? "Updates on" : "Muted").font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                        }
                    }
                    Toggle("Allow updates", isOn: Binding(get: { sub.notificationsEnabled }, set: { enabled in
                        PocketHaptics.selection(); Task { await backend.notificationPreference(sub, enabled: enabled) }
                    }))
                    Button("Disconnect app", role: .destructive) { disconnecting = sub }
                }
            }
        }
        .pocketList().navigationTitle("App updates").navigationBarTitleDisplayMode(.inline).disabled(backend.busy)
        .confirmationDialog("Disconnect this app?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
            if let sub = disconnecting { Button("Disconnect", role: .destructive) { Task { await backend.disconnect(sub); disconnecting = nil } } }
            Button("Cancel", role: .cancel) { disconnecting = nil }
        } message: { Text("You can connect it again later.") }
    }
}

struct RegisteredAppDetail: View {
    let id: String
    let open: (String) -> Void
    @EnvironmentObject private var backend: Backend
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var consenting = false
    @State private var pairing: PairingReply?
    @State private var pairingBusy = false
    @State private var deleting = false
    private var app: RegisteredApp? { backend.apps.first { $0.id == id } }

    var body: some View {
        Group {
            if let app {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            AppIdentity(app: app, size: 76)
                            Text(app.name).font(.pocketDisplay)
                            Text(app.url?.host ?? "Web app").font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                            if !app.summary.isEmpty { Text(app.summary).font(.pocketBody).foregroundStyle(PocketStyle.secondaryInk) }
                            if app.kind == .native {
                                Text("This older native app is no longer supported.").font(.pocketBody).foregroundStyle(PocketStyle.secondaryInk)
                            } else {
                                Button { open(id) } label: { PrimaryButtonLabel(title: "Open app", symbol: "arrow.up.right") }
                                    .buttonStyle(PocketPressStyle())
                                Button(home.state.pinned.contains(id) ? "Unpin from Home" : "Pin to Home", systemImage: "pin") { home.pin(id) }
                                ShareLink(item: app.miniApp.deepLink) { Label("Share Pocket link", systemImage: "square.and.arrow.up") }
                            }
                        }.padding(.vertical, 8)
                    }

                    if app.manifest != nil {
                        Section("Updates") {
                            if let sub = backend.subscriptions.first(where: { $0.appId == id }) {
                                Toggle("Allow updates", isOn: Binding(get: { sub.notificationsEnabled }, set: { value in Task { await backend.notificationPreference(sub, enabled: value) } }))
                                Button("Disconnect updates", role: .destructive) { Task { await backend.disconnect(sub); pairing = nil } }
                            } else {
                                Button("Connect updates", systemImage: "bell.badge") { consenting = true }.disabled(pairingBusy)
                            }
                            if let pairing {
                                Text("Enter this one-use code on the app’s website. It expires in five minutes.").font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                                Text(pairing.pairingCode).font(.body.monospaced()).textSelection(.enabled)
                                Button("Copy code") {
                                    UIPasteboard.general.setItems([["public.utf8-plain-text": pairing.pairingCode]], options: [.localOnly: true, .expirationDate: Date(timeIntervalSince1970: pairing.expiresAt)])
                                }
                            }
                        }
                    }

                    if app.owner == backend.username {
                        Section("Share access") {
                            TextField("Pocket username", text: $recipient).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Grant access") { Task { if await backend.share(app, with: recipient) { recipient = "" } } }.disabled(recipient.isEmpty)
                            ForEach(app.sharedWith, id: \.self) { user in
                                HStack { Text(user); Spacer(); Button("Revoke", role: .destructive) { Task { await backend.revoke(app, recipient: user) } } }
                            }
                        }
                        Section { Button("Delete app", role: .destructive) { deleting = true } }
                    }
                }
                .pocketList().navigationTitle("App details").navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Delete \(app.name)?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete app", role: .destructive) { Task { if await backend.delete(app) { dismiss() } } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This removes the listing and its shared access.") }
                .confirmationDialog("Allow updates from \(app.name)?", isPresented: $consenting, titleVisibility: .visible) {
                    Button("Create pairing code") {
                        Task {
                            pairingBusy = true; defer { pairingBusy = false }
                            do { pairing = try await backend.pairing(appId: id) }
                            catch { if !isRequestCancellation(error) { backend.error = error.localizedDescription } }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("You can mute or disconnect updates at any time.") }
            } else {
                ContentUnavailableView("App unavailable", systemImage: "lock")
            }
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
    @State private var signingOut = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                Text("You").font(.pocketDisplay).accessibilityAddTraits(.isHeader)
                HStack(spacing: 14) {
                    AppMark(name: username, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@" + username).font(.pocketTitle)
                        Text("Pocket account").font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                    }
                }.padding(.vertical, 8)
                HStack(spacing: 10) {
                    StatCard(value: backend.apps.filter { $0.owner == username }.count, label: "Your apps")
                    StatCard(value: backend.apps.filter { $0.owner != username }.count, label: "Shared")
                }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)

            Section("Settings") {
                SettingsRow(symbol: "moon.fill", title: "Appearance", detail: "Dark")
                NavigationLink { NotificationSettings() } label: {
                    SettingsRow(symbol: "bell", title: "App updates", detail: "\(backend.subscriptions.count) connected")
                }
                Button { Task { await notifications.requestPermission() } } label: {
                    SettingsRow(symbol: "app.badge", title: "Device notifications", detail: notifications.status)
                }.buttonStyle(.plain)
                Button { serverSheet = true } label: {
                    SettingsRow(symbol: "network", title: "Connection", detail: URL(string: backend.address)?.host ?? "Pocket server")
                }.buttonStyle(.plain)
            }

            Section("About") {
                NavigationLink("Privacy & data") { PrivacyView() }
                NavigationLink("Terms") { TermsView() }
                LabeledContent("Version", value: version.replacingOccurrences(of: "Version ", with: ""))
            }

            Section { Button("Sign out", role: .destructive) { signingOut = true } }
        }
        .listStyle(.insetGrouped).pocketList().toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $serverSheet) { ConnectionSettings() }
        .confirmationDialog("Sign out of Pocket?", isPresented: $signingOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await backend.logout() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Open website sessions will close.") }
    }
}

private struct ConnectionSettings: View {
    @EnvironmentObject private var backend: Backend
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connection").font(.pocketDisplay)
                    TextField("Server address", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(15).background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.fieldRadius))
                        .overlay(RoundedRectangle(cornerRadius: PocketStyle.fieldRadius).stroke(PocketStyle.line))
                    Text("Changing servers signs you out.").font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                    Button { backend.changeServer(address); dismiss() } label: { PrimaryButtonLabel(title: "Use this server") }
                        .buttonStyle(PocketPressStyle()).disabled(address.isEmpty || address == backend.address)
                }.padding(20)
            }
            .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.onAppear { address = backend.address }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section("Pocket account") { Text("Pocket stores your account, app listings, sharing access, and activity needed to run the service.") }
            Section("Mini apps") { Text("Each mini app runs in its own temporary web session. Pocket does not inject your Pocket password or account token into websites.") }
            Section("On this device") { Text("Signing out clears open web sessions. Recent app metadata can remain in your Pocket account’s local preferences.") }
        }.pocketList().navigationTitle("Privacy & data").navigationBarTitleDisplayMode(.inline)
    }
}

private struct TermsView: View {
    var body: some View {
        List {
            Section { Text("Pocket opens creator-hosted and third-party websites. Those sites keep their own accounts, data, and terms.") }
            Section { Text("Only add and share apps you are allowed to use. Public starter apps are provided as links, not endorsements.") }
        }.pocketList().navigationTitle("Terms").navigationBarTitleDisplayMode(.inline)
    }
}

private struct OnboardingView: View {
    let complete: () -> Void
    @State private var page = 0
    private let pages = [
        OnboardingPage(symbol: "square.grid.2x2", title: "Your apps"),
        OnboardingPage(symbol: "arrow.up.right.square", title: "Open full screen"),
        OnboardingPage(symbol: "bell", title: "Updates when you choose")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Button("Skip") { complete() }.font(.pocketHeadline) }.padding(20)
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: item.symbol).font(.system(size: 46, weight: .medium)).foregroundStyle(PocketStyle.accent)
                        Text(item.title).font(.pocketDisplay)
                    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .always))
            Button {
                if page == pages.count - 1 { complete() }
                else { withAnimation(.easeInOut(duration: 0.2)) { page += 1 } }
            } label: { PrimaryButtonLabel(title: page == pages.count - 1 ? "Get started" : "Continue") }
            .buttonStyle(PocketPressStyle()).padding(20)
        }.background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
    }
}

private struct OnboardingPage { let symbol: String; let title: String }

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(PocketStyle.secondaryInk)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(PocketStyle.secondaryInk))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(PocketStyle.ink)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(PocketStyle.secondaryInk).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.fieldRadius))
        .overlay(RoundedRectangle(cornerRadius: PocketStyle.fieldRadius).stroke(PocketStyle.line))
    }
}

private struct QuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View { Button(action: action) { QuickActionLabel(title: title, symbol: symbol) }.buttonStyle(PocketPressStyle()) }
}

private struct QuickActionLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(PocketStyle.accent)
            Text(title).font(.pocketCaption).foregroundStyle(PocketStyle.ink).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PocketStyle.cardRadius).stroke(PocketStyle.line))
    }
}

private struct AppListLabel<Icon: View>: View {
    let name: String
    let detail: String
    @ViewBuilder let icon: () -> Icon
    var body: some View {
        HStack(spacing: 14) {
            icon()
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.pocketHeadline).foregroundStyle(PocketStyle.ink)
                Text(detail).font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk).lineLimit(1)
            }
        }.padding(.vertical, 5)
    }
}

struct PrimaryButtonLabel: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if let symbol { Image(systemName: symbol) }
        }
        .font(.pocketHeadline).frame(maxWidth: .infinity).frame(height: 52)
        .foregroundStyle(.white).background(PocketStyle.accent, in: RoundedRectangle(cornerRadius: PocketStyle.fieldRadius))
    }
}

private struct EmptyAppsView: View {
    let searching: Bool
    let add: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: searching ? "magnifyingglass" : "square.grid.2x2").font(.system(size: 30)).foregroundStyle(PocketStyle.accent)
            Text(searching ? "No matching apps" : "No apps yet").font(.pocketTitle)
            if !searching { Button("Add app", action: add).font(.pocketHeadline) }
        }.padding(.vertical, 18)
    }
}

private struct SkeletonAppRow: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14).fill(PocketStyle.soft).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(PocketStyle.soft).frame(width: 130, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(PocketStyle.soft).frame(width: 90, height: 10)
            }
        }.redacted(reason: .placeholder).padding(.vertical, 7)
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.pocketHeadline).padding(.horizontal, 16).padding(.vertical, 12)
            .background(PocketStyle.elevated, in: Capsule()).overlay(Capsule().stroke(PocketStyle.line))
    }
}

private struct StatCard: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.pocketTitle).monospacedDigit()
            Text(label).font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PocketStyle.cardRadius).stroke(PocketStyle.line))
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 26).foregroundStyle(PocketStyle.accent)
            Text(title).foregroundStyle(PocketStyle.ink)
            Spacer()
            Text(detail).font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk).lineLimit(1)
        }
    }
}
