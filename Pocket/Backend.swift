import SwiftUI
import Security
import PhotosUI

struct GeneratedAppSpec: Codable, Hashable {
    struct Appearance: Codable, Hashable {
        let icon: String?
        let theme: String?
        let background: String?
        let layout: String?
    }

    let appearance: Appearance?
}

struct RegisteredApp: Identifiable, Codable, Hashable {
    let id: String
    let owner: String
    let name: String
    let url: URL?
    let kind: AppKind?
    let revision: Int?
    let creatorKey: String?
    let manifest: WebManifest?
    let spec: GeneratedAppSpec?
    let generated: Bool?
    let supported: Bool?
    let summary: String
    let sharedWith: [String]
    var miniApp: MiniApp { MiniApp(id: id, name: name, icon: "app.fill", url: url ?? URL(string: "pocket://app/\(id)")!, community: "", summary: summary, kind: kind) }
}

private struct AuthReply: Decodable { let token: String; let username: String }
private struct AppsReply: Decodable { let apps: [RegisteredApp] }
private struct UserReply: Decodable { let username: String }
private struct AccessReply: Decodable { let url: URL }
private struct BuildJobReply: Decodable { let id: String; let status: String; let error: String? }
private struct PublishReply: Decodable { let appId: String }
private struct OKReply: Decodable { let ok: Bool }
private struct ErrorReply: Decodable { let error: String }

/// View lifecycle and superseded-session cancellations are not user-facing failures.
func isRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let value = error as NSError
    return value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled
}

@MainActor final class Backend: ObservableObject {
    @Published var pendingURL: URL?
    @Published var inbox: [InboxEntry] = []
    @Published var subscriptions: [NotificationSubscription] = []
    @Published var unreadCount = 0
    @Published var nextCursor: String?
    @Published var deliveryMode = "local"
    private var activityGeneration = UUID()
    private var activityFilter: String?
    let home = HomeStore()
    var identity: String { address + "|" + (username ?? "") }
    private let transport = BackendTransport()
    @Published var username: String?
    @Published var apps: [RegisteredApp] = []
    @Published var error: String?
    @Published var busy = false
    @Published private(set) var address: String
    private var token: String?
    private let service = "dev.local.pocket.session"
    init() {
        address = UserDefaults.standard.string(forKey: "pocket.server") ?? "https://pockett.orkis.tech"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: address, kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data { token = String(data: data, encoding: .utf8) }
    }
    private func saveToken(_ value: String?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: address]
        SecItemDelete(query as CFDictionary)
        if let value {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw failure("Could not save your session. Please try again.") }
        }
        token = value
        if value == nil { clearLocalSession() }
    }
    private func clearLocalSession() {
        WebSessionPool.shared.clear(); home.clearSession(); WidgetPublisher.clear()
        activityGeneration = UUID(); activityFilter = nil
        inbox = []; subscriptions = []; unreadCount = 0; nextCursor = nil; pendingURL = nil
        PocketNotifications.shared.clearSession()
    }

    private func failure(_ message: String) -> NSError { NSError(domain: "Pocket", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func requestData(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard let url = URL(string: address + "/" + path) else { throw failure("Check the server address in Profile.") }
        let requestAddress = address, requestToken = token
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await transport.session.data(for: request)
        try Task.checkCancellation()
        guard address == requestAddress, token == requestToken else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw failure("Invalid server response.") }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 && path != "login" && path != "signup" {
                let incoming = pendingURL
                try? saveToken(nil); username = nil; apps = []
                pendingURL = incoming
            }
            if response.statusCode == 403 || response.statusCode == 404 {
                let parts = path.components(separatedBy: "/")
                if parts.first == "apps", parts.count == 2 { WebSessionPool.shared.remove(parts[1]) }
            }
            throw failure((try? JSONDecoder().decode(ErrorReply.self, from: data).error) ?? "Request failed (\(response.statusCode)).")
        }
        return data
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        try await JSONDecoder().decode(T.self, from: requestData(path, method: method, body: body))
    }
    @discardableResult func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        do { try await operation(); return true }
        catch {
            if !isRequestCancellation(error) { self.error = error.localizedDescription }
            return false
        }
    }
    private func fetchApps() async throws {
        let reply: AppsReply = try await request("apps")
        apps = reply.apps
        let ids = Set(apps.map(\.id))
        if let username {
            home.use(server: address, account: username); home.retain(ids)
            WebSessionPool.shared.use(identity: identity); WebSessionPool.shared.retain(ids)
            WidgetPublisher.publish(apps.filter { $0.kind != .native }, account: username, server: address)
        }
    }
    func refreshActivity(more: Bool = false, appId: String? = nil, setFilter: Bool = false) async {
        guard token != nil else { return }
        if setFilter { activityFilter = appId }
        let appId = appId ?? activityFilter
        let generation = UUID(); activityGeneration = generation
        do {
            var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "limit", value: "50")]
            if more, let nextCursor { parts.queryItems?.append(URLQueryItem(name: "before", value: nextCursor)) }
            if let appId { parts.queryItems?.append(URLQueryItem(name: "appId", value: appId)) }
            let reply: InboxReply = try await request("notification-inbox?" + (parts.percentEncodedQuery ?? ""))
            guard generation == activityGeneration else { return }
            if more { inbox.append(contentsOf: reply.entries.filter { item in !inbox.contains(where: { $0.id == item.id }) }) }
            else { inbox = reply.entries }
            nextCursor = reply.nextCursor; unreadCount = reply.unreadCount
            let prefs: SubscriptionReply = try await request("notification-subscriptions")
            guard generation == activityGeneration else { return }; subscriptions = prefs.subscriptions
        } catch { if generation == activityGeneration && !isRequestCancellation(error) { self.error = error.localizedDescription } }
    }
    func pairing(appId: String) async throws -> PairingReply { try await request("apps/\(appId)/pairings", method: "POST", body: ["consent": true]) }
    func notificationPreference(_ subscription: NotificationSubscription, enabled: Bool) async {
        await perform {
            let _: NotificationSubscription = try await self.request("notification-subscriptions/\(subscription.id)/preferences", method: "POST", body: ["notificationsEnabled": enabled])
            await self.refreshActivity()
        }
    }
    func disconnect(_ subscription: NotificationSubscription) async {
        await perform {
            let _: OKReply = try await self.request("notification-subscriptions/\(subscription.id)", method: "DELETE")
            await self.refreshActivity()
        }
    }
    func registerDevice(token: String, environment: String) async {
        guard username != nil else { return }
        do {
            let reply: DeviceReply = try await request("notification-devices", method: "POST", body: ["deviceId": PocketNotifications.shared.deviceID, "token": token, "environment": environment])
            deliveryMode = reply.deliveryMode
        } catch {
            if !isRequestCancellation(error) { self.error = "Device registration failed. Activity is still available while Pocket is open." }
        }
    }
    func launch(_ id: String, event: String? = nil) async -> AppLaunch? {
        var launch: AppLaunch?
        await perform {
            let listing: RegisteredApp = try await self.request("apps/\(id)")
            guard listing.kind != .native, let entry = listing.url else { throw self.failure("This older native app is no longer supported. Its stored records have been preserved.") }
            var exact: URL?
            var accessFragment: String?
            if listing.generated == true {
                let access: AccessReply = try await self.request("apps/\(id)/access", method: "POST", body: [:])
                guard WebPolicy.safe(access.url, for: entry) else { throw self.failure("Invalid app access link.") }
                exact = access.url
                accessFragment = access.url.fragment
            }
            if let event {
                let target: NotificationLaunch = try await self.request("notification-inbox/\(event)/launch")
                guard target.appId == id, WebPolicy.safe(target.url, for: entry) else { throw self.failure("This notification link is unavailable.") }
                exact = target.url
                let _: OKReply = try await self.request("notification-inbox/\(event)/read", method: "POST", body: [:])
                if let i = self.inbox.firstIndex(where: { $0.eventId == event }), !self.inbox[i].read { self.inbox[i].read = true; self.unreadCount = max(0,self.unreadCount-1) }
            }
            if let accessFragment, let destination = exact,
               var components = URLComponents(url: destination, resolvingAgainstBaseURL: false) {
                components.fragment = accessFragment
                exact = components.url
            }
            self.home.opened(id)
            launch = AppLaunch(app: listing.miniApp, exactTarget: exact)
        }
        return launch
    }

    func restore() async {
        guard token != nil else { WidgetPublisher.clear(); return }
        await perform {
            let user: UserReply = try await self.request("me")
            self.username = user.username
            try await self.fetchApps()
            await self.refreshActivity()
        }
    }
    func refresh() async {
        guard token != nil else { return }
        await restore()
    }
    func authenticate(username: String, password: String, signup: Bool) async {
        await perform {
            let reply: AuthReply = try await self.request(signup ? "signup" : "login", method: "POST", body: ["username": username, "password": password])
            try self.saveToken(reply.token)
            let incoming = self.pendingURL
            self.clearLocalSession()
            self.pendingURL = incoming
            self.username = reply.username
            self.apps = []
            try await self.fetchApps()
        }
    }
    func logout() async {
        WebSessionPool.shared.clear()
        PocketNotifications.shared.clearSession()
        await perform {
            let _: OKReply? = try? await self.request("logout", method: "POST", body: [:])
            try self.saveToken(nil); self.username = nil; self.apps = []
        }
    }
    func changeServer(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URLComponents(string: value), (url.scheme == "http" || url.scheme == "https"), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty else {
            error = "Enter a server address such as https://pockett.orkis.tech"; return
        }
        let incoming = pendingURL
                try? saveToken(nil); username = nil; apps = []
                pendingURL = incoming; error = nil
        address = value; UserDefaults.standard.set(value, forKey: "pocket.server")
    }
    func register(name: String, url: String, summary: String) async -> RegisteredApp? {
        var created: RegisteredApp?
        let succeeded = await perform {
            created = try await self.request("apps", method: "POST", body: ["name": name, "url": url, "summary": summary])
            try await self.fetchApps()
        }
        return succeeded ? created : nil
    }
    func createMiniApp(prompt: String, icon: String, theme: String, background: String, layout: String) async -> Bool {
        await perform {
            var request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let choices = [("icon", icon), ("color theme", theme), ("background", background), ("item layout", layout)]
                .filter { $0.1 != "Automatic" }
                .map { "\($0.0): \($0.1)" }
            if !choices.isEmpty { request += "\nAppearance preferences: " + choices.joined(separator: ", ") + "." }
            let created: BuildJobReply = try await self.request("jobs", method: "POST", body: ["prompt": request])
            let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(120))
            while clock.now < deadline {
                try Task.checkCancellation()
                let job: BuildJobReply = try await self.request("jobs/\(created.id)")
                if job.status == "ready" {
                    let _: PublishReply = try await self.request("jobs/\(created.id)/publish", method: "POST", body: [:])
                    try await self.fetchApps()
                    return
                }
                if job.status == "failed" {
                    throw self.failure(job.error ?? "Pocket couldn't build this app. Try describing it another way.")
                }
                try await Task.sleep(for: .seconds(2))
            }
            throw self.failure("This build is taking longer than expected. It is still saved on the server.")
        }
    }
    func share(_ app: RegisteredApp, with recipient: String) async -> Bool {
        await perform {
            let _: OKReply = try await self.request("apps/\(app.id)/shares", method: "POST", body: ["username": recipient])
            try await self.fetchApps()
        }
    }
    func revoke(_ app: RegisteredApp, recipient: String) async {
        await perform {
            let _: OKReply = try await self.request("apps/\(app.id)/shares/\(recipient)", method: "DELETE")
            try await self.fetchApps()
        }
    }
    func delete(_ app: RegisteredApp) async -> Bool {
        guard app.owner == username else { error = "Only the app owner can delete this listing."; return false }
        return await perform {
            let _: OKReply = try await self.request("apps/\(app.id)", method: "DELETE")
            WebSessionPool.shared.remove(app.id)
            CustomAppIconStore.remove(app.id)
            try await self.fetchApps()
        }
    }

}

struct AccountForm: View {
    @EnvironmentObject private var backend: Backend
    @State private var username = ""
    @State private var password = ""
    @State private var signup = false
    @State private var showPassword = false
    @State private var submitted = false
    @State private var server = ""
    @FocusState private var focused: Field?
    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PixelHeroHeader(
                    eyebrow: "Pocket",
                    title: signup ? "Make Pocket yours." : "Welcome back.",
                    message: signup ? "Create an account for your apps and saved places." : "Sign in to pick up where you left off."
                ) { EmptyView() }

                VStack(alignment: .leading, spacing: 22) {
                    Picker("Account", selection: $signup) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }.pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("", text: $username, prompt: Text("Username").foregroundStyle(PocketStyle.secondaryInk))
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .username).submitLabel(.next)
                            .onSubmit { focused = .password }
                            .pocketField()
                        if submitted && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Enter your username.").font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                        }

                        HStack(spacing: 8) {
                            Group {
                                if showPassword {
                                    TextField("", text: $password, prompt: Text("Password").foregroundStyle(PocketStyle.secondaryInk)).textContentType(signup ? .newPassword : .password)
                                } else {
                                    SecureField("", text: $password, prompt: Text("Password").foregroundStyle(PocketStyle.secondaryInk)).textContentType(signup ? .newPassword : .password)
                                }
                            }
                            .focused($focused, equals: .password).submitLabel(.go)
                            .onSubmit { authenticate() }
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye").frame(width: 32, height: 32)
                            }.accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }.pocketField()
                        if submitted && password.count < 8 {
                            Text("Use at least 8 characters.").font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                        }
                    }

                    Button(action: authenticate) {
                        PrimaryButtonLabel(title: backend.busy ? "Signing in…" : (signup ? "Create account" : "Sign in"))
                    }.buttonStyle(PocketPressStyle()).disabled(backend.busy)

                    if let error = backend.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                    }

                    DisclosureGroup("Connection") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("", text: $server, prompt: Text("Server address").foregroundStyle(PocketStyle.secondaryInk))
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().pocketField()
                            Button("Use this server") { backend.changeServer(server) }.disabled(server == backend.address)
                            Text("Changing servers signs you out.").font(.pocketCaption).foregroundStyle(PocketStyle.secondaryInk)
                        }.padding(.top, 10)
                    }
                    .font(.pocketHeadline)
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 48)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
        .toolbar(.hidden, for: .navigationBar)
        .pocketHeroStatusBar()
        .sensoryFeedback(.selection, trigger: signup)
        .onAppear { server = backend.address }
    }

    private func authenticate() {
        submitted = true
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty, password.count >= 8, !backend.busy else { return }
        focused = nil
        Task {
            await backend.authenticate(username: cleanUsername, password: password, signup: signup)
            if backend.username != nil { password = ""; PocketHaptics.success() }
        }
    }
}

struct AddAppView: View {
    @EnvironmentObject private var backend: Backend
    @Environment(\.dismiss) private var dismiss
    let importMode: Bool
    let onAdded: () -> Void

    init(importMode: Bool = false, onAdded: @escaping () -> Void = {}) {
        self.importMode = importMode
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            if importMode {
                ExistingAppView(title: "Import app", buttonTitle: "Import app") { finish() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Add app").font(.pocketDisplay)
                        VStack(spacing: 12) {
                            NavigationLink { CreateMiniAppView { finish() } } label: {
                                AddAppChoice(icon: "plus", title: "Create with agent", accent: PocketStyle.accent)
                            }
                            NavigationLink { ExistingAppView { finish() } } label: {
                                AddAppChoice(icon: "arrow-up-right", title: "Add existing app", accent: PocketStyle.elevated)
                            }
                        }.buttonStyle(PocketPressStyle())
                    }
                    .padding(20).frame(maxWidth: 540).frame(maxWidth: .infinity)
                }
                .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
        .interactiveDismissDisabled(backend.busy)
    }

    private func finish() {
        onAdded()
        dismiss()
    }
}

private struct AddAppChoice: View {
    let icon: String
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            PocketIcon(icon, size: 22).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(accent, in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.pocketHeadline).foregroundStyle(PocketStyle.ink)
            Spacer()
            PocketIcon("chevron-right", size: 18).foregroundStyle(PocketStyle.secondaryInk)
        }
        .padding(14)
        .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PocketStyle.cardRadius).stroke(PocketStyle.line))
    }
}

private struct CreateMiniAppView: View {
    @EnvironmentObject private var backend: Backend
    let finished: () -> Void
    @State private var prompt = ""
    @State private var icon = "Automatic"
    @State private var theme = "Automatic"
    @State private var background = "Automatic"
    @State private var layout = "Automatic"
    @FocusState private var focused: Bool
    private let icons: [CreationIconOption] = [
        .init(title: "Automatic", asset: nil),
        .init(title: "Check", asset: "check"),
        .init(title: "Notebook", asset: "notebook-pen"),
        .init(title: "Calendar", asset: "calendar-days"),
        .init(title: "Wallet", asset: "wallet"),
        .init(title: "Timer", asset: "timer"),
        .init(title: "Book", asset: "book-open"),
        .init(title: "Person", asset: "user-round"),
        .init(title: "Grid", asset: "grid-2x2"),
        .init(title: "Inbox", asset: "inbox"),
        .init(title: "Bell", asset: "bell")
    ]
    private let themes = ["Automatic", "Forest", "Ember", "Ocean", "Violet", "Paper"]
    private let backgrounds = ["Automatic", "Soft glow", "Color mesh", "Fine grid", "Plain"]
    private let layouts = ["Automatic", "Cards", "Rows"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Create app").font(.pocketDisplay)
                TextField("", text: $prompt, prompt: Text("Describe the app you need").foregroundStyle(PocketStyle.secondaryInk), axis: .vertical)
                    .lineLimit(4...8).focused($focused).pocketField()

                VStack(alignment: .leading, spacing: 14) {
                    Text("App icon").font(.pocketHeadline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(icons) { option in
                            Button {
                                icon = option.title
                                PocketHaptics.selection()
                            } label: {
                                VStack(spacing: 7) {
                                    Group {
                                        if let asset = option.asset {
                                            PocketIcon(asset, size: 22)
                                        } else {
                                            Image(systemName: "wand.and.stars").font(.system(size: 20, weight: .medium))
                                        }
                                    }
                                    .frame(height: 24)
                                    Text(option.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                }
                                .foregroundStyle(icon == option.title ? Color.white : PocketStyle.ink)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(icon == option.title ? PocketStyle.accent : PocketStyle.elevated, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(icon == option.title ? PocketStyle.accent : PocketStyle.line))
                            }
                            .buttonStyle(PocketPressStyle())
                            .accessibilityLabel(option.title + " icon")
                            .accessibilityAddTraits(icon == option.title ? .isSelected : [])
                        }
                    }
                    VStack(spacing: 4) {
                        darkPicker("Color", selection: $theme, values: themes)
                        darkPicker("Background", selection: $background, values: backgrounds)
                        darkPicker("Layout", selection: $layout, values: layouts)
                    }
                }
                .padding(14)
                .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: PocketStyle.cardRadius).stroke(PocketStyle.line))

                Button {
                    focused = false
                    Task {
                        if await backend.createMiniApp(prompt: prompt, icon: icon, theme: theme, background: background, layout: layout) {
                            PocketHaptics.success(); finished()
                        }
                    }
                } label: {
                    PrimaryButtonLabel(title: backend.busy ? "Building app…" : "Create app")
                }
                .buttonStyle(PocketPressStyle())
                .disabled(backend.busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)

                if let error = backend.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                }
            }
            .padding(20).frame(maxWidth: 540).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(backend.busy)
        .disabled(backend.busy)
        .onAppear { focused = true }
    }

    private func darkPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        HStack {
            Text(title).font(.pocketBody).foregroundStyle(PocketStyle.secondaryInk)
            Spacer()
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { Text($0) }
            }
            .labelsHidden()
            .tint(PocketStyle.accent)
        }
        .padding(.vertical, 2)
    }
}

private struct CreationIconOption: Identifiable {
    let title: String
    let asset: String?
    var id: String { title }
}

private struct ExistingAppView: View {
    @EnvironmentObject private var backend: Backend
    let title: String
    let buttonTitle: String
    let finished: () -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var summary = ""
    @State private var iconItem: PhotosPickerItem?
    @State private var iconData: Data?
    @State private var iconError: String?
    @State private var submitted = false
    @FocusState private var focused: Field?
    private enum Field { case name, url, summary }

    init(title: String = "Add existing app", buttonTitle: String = "Add app", finished: @escaping () -> Void) {
        self.title = title
        self.buttonTitle = buttonTitle
        self.finished = finished
    }

    private var validURL: Bool {
        guard let parts = URLComponents(string: url), parts.scheme == "https", parts.host != nil else { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.pocketDisplay)
                PhotosPicker(selection: $iconItem, matching: .images) {
                    HStack(spacing: 14) {
                        iconPreview
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name.isEmpty ? "App icon" : name).font(.pocketTitle).lineLimit(1)
                            Text(iconData == nil ? "Choose picture" : "Change picture")
                                .font(.pocketCaption).foregroundStyle(PocketStyle.accent)
                        }
                        Spacer()
                        Image(systemName: "photo.on.rectangle").font(.title3).foregroundStyle(PocketStyle.secondaryInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PocketPressStyle())
                .accessibilityLabel(iconData == nil ? "Choose app picture" : "Change app picture")
                .onChange(of: iconItem) { _, item in loadIcon(item) }
                VStack(alignment: .leading, spacing: 10) {
                    field("App name", text: $name, focus: .name)
                    VStack(alignment: .leading, spacing: 6) {
                        field("Website URL", text: $url, focus: .url)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if submitted && !validURL {
                            Text("Enter a complete HTTPS URL.").font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                        }
                    }
                    TextField("", text: $summary, prompt: Text("Description (optional)").foregroundStyle(PocketStyle.secondaryInk), axis: .vertical)
                        .lineLimit(2...4).focused($focused, equals: .summary).pocketField()
                }

                Button(action: addApp) {
                    PrimaryButtonLabel(title: backend.busy ? "Adding app…" : buttonTitle)
                }
                .buttonStyle(PocketPressStyle())
                .disabled(backend.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validURL)

                if let error = backend.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                }
                if let iconError {
                    Label(iconError, systemImage: "photo.badge.exclamationmark")
                        .font(.pocketCaption).foregroundStyle(PocketStyle.danger)
                }
            }
            .padding(20).frame(maxWidth: 540).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(backend.busy)
        .disabled(backend.busy)
        .onAppear { focused = .name }
    }

    private func field(_ placeholder: String, text: Binding<String>, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(PocketStyle.secondaryInk))
                .focused($focused, equals: focus).pocketField()
            if submitted && focus == .name && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Enter an app name.").font(.pocketCaption).foregroundStyle(PocketStyle.danger)
            }
        }
    }

    @ViewBuilder private var iconPreview: some View {
        if let iconData, let image = UIImage(data: iconData) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(PocketStyle.line))
        } else {
            FaviconMark(name: name.isEmpty ? "App" : name, url: validURL ? URL(string: url) : nil, size: 64)
        }
    }

    private func loadIcon(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let prepared = CustomAppIconStore.prepare(data) else {
                    iconError = "Choose a valid image."
                    return
                }
                iconData = prepared
                iconError = nil
                PocketHaptics.selection()
            } catch {
                iconError = "Could not load that image."
            }
        }
    }

    private func addApp() {
        submitted = true
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, validURL, !backend.busy else { return }
        focused = nil
        Task {
            if let app = await backend.register(name: cleanName, url: cleanURL, summary: summary.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if let iconData { CustomAppIconStore.save(iconData, for: app.id) }
                PocketHaptics.success(); finished()
            }
        }
    }
}

private extension View {
    func pocketField() -> some View {
        padding(.horizontal, 14).frame(minHeight: 50)
            .background(PocketStyle.surface, in: RoundedRectangle(cornerRadius: PocketStyle.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: PocketStyle.fieldRadius).stroke(PocketStyle.line))
            .foregroundStyle(PocketStyle.ink)
    }
}


/// Pocket account credentials stay on this dedicated transport and never follow redirects.
final class BackendTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
