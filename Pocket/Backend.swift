import SwiftUI
import Security

struct RegisteredApp: Identifiable, Codable, Hashable {
    let id: String
    let owner: String
    let name: String
    let url: URL?
    let kind: AppKind?
    let revision: Int?
    let creatorKey: String?
    let manifest: WebManifest?
    let supported: Bool?
    let summary: String
    let sharedWith: [String]
    var miniApp: MiniApp { MiniApp(id: id, name: name, icon: "app.fill", url: url ?? URL(string: "pocket://app/\(id)")!, community: "", summary: summary, kind: kind) }
}

private struct AuthReply: Decodable { let token: String; let username: String }
private struct AppsReply: Decodable { let apps: [RegisteredApp] }
private struct UserReply: Decodable { let username: String }
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
        address = UserDefaults.standard.string(forKey: "pocket.server") ?? "http://localhost:8787"
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
            if let event {
                let target: NotificationLaunch = try await self.request("notification-inbox/\(event)/launch")
                guard target.appId == id, WebPolicy.safe(target.url, for: entry) else { throw self.failure("This notification link is unavailable.") }
                exact = target.url
                let _: OKReply = try await self.request("notification-inbox/\(event)/read", method: "POST", body: [:])
                if let i = self.inbox.firstIndex(where: { $0.eventId == event }), !self.inbox[i].read { self.inbox[i].read = true; self.unreadCount = max(0,self.unreadCount-1) }
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
            error = "Enter a server address such as http://your-mac.local:8787"; return
        }
        let incoming = pendingURL
                try? saveToken(nil); username = nil; apps = []
                pendingURL = incoming; error = nil
        address = value; UserDefaults.standard.set(value, forKey: "pocket.server")
    }
    func register(name: String, url: String, summary: String) async -> Bool {
        await perform {
            let _: RegisteredApp = try await self.request("apps", method: "POST", body: ["name": name, "url": url, "summary": summary])
            try await self.fetchApps()
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

}

struct AccountForm: View {
    @EnvironmentObject private var backend: Backend
    @State private var username = ""
    @State private var password = ""
    @State private var signup = false
    @State private var server = ""
    @ObservedObject private var notifications = PocketNotifications.shared
    var body: some View {
        List {
            if let user = backend.username {
                Section {
                    HStack(spacing: 16) {
                        AppMark(name: user, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user).font(.pocketTitle)
                            Text("Your Pocket account").font(.pocketSubheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 12)
                    LabeledContent("Registered apps", value: "\(backend.apps.filter { $0.owner == user }.count)")
                    LabeledContent("Shared with you", value: "\(backend.apps.filter { $0.owner != user }.count)")
                    Button("Sign out") { Task { await backend.logout() } }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        PocketArt(name: "pocket-folded-world").frame(height: 270).clipped().padding(.horizontal, -20)
                        Text("Small apps.\nA place of their own.").font(.pocketDisplay).tracking(-0.8).foregroundStyle(PocketStyle.ink)
                        Text("Your apps, saved places, and little everyday tools. All in Pocket.")
                            .font(.pocketBody).foregroundStyle(.secondary)
                    }.padding(.vertical, 20)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                Section {
                    Picker("Account", selection: $signup) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }.pickerStyle(.segmented)
                    TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password (8+ characters)", text: $password).textContentType(signup ? .newPassword : .password)
                    Button(signup ? "Create account" : "Sign in") {
                        Task {
                            await backend.authenticate(username: username, password: password, signup: signup)
                            if backend.username != nil { password = ""; PocketHaptics.success() }
                        }
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .disabled(username.isEmpty || password.count < 8)
                    if backend.busy { ProgressView("Signing in…") }
                    if let error = backend.error {
                        Text(error).font(.pocketSubheadline).foregroundStyle(.red)
                    }
                }
            }
            if backend.username != nil {
            Section("Notifications") {
                Text(notifications.status)
                Button("Enable device notifications") { Task { await PocketNotifications.shared.requestPermission() } }
                Text("Activity refreshes while Pocket is open. Website Web Push is not connected to this inbox.").font(.pocketCaption).foregroundStyle(.secondary)
            }
            Section("Home Screen widget") {
                Text("Touch and hold your Home Screen, tap Edit → Add Widget, then choose Pocket.")
                Text("The widget shows your apps and apps shared with you. Refresh Home to update its list.").font(.pocketCaption).foregroundStyle(.secondary)
            }
            }
            Section {
                DisclosureGroup("Test server") {
                TextField("Server address", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Use this server") { backend.changeServer(server) }.disabled(server == backend.address)
                Text("Use the same server on both devices. Changing servers signs you out.").font(.pocketCaption).foregroundStyle(.secondary)
                }
            }
        }.pocketList().navigationTitle(backend.username == nil ? "Pocket" : "Profile")
            .navigationBarTitleDisplayMode(.inline).disabled(backend.busy)
            .sensoryFeedback(.selection, trigger: signup)
            .onAppear { server = backend.address }
    }
}

struct AddAppView: View {
    @EnvironmentObject private var backend: Backend
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var summary = ""
    var body: some View {
        NavigationStack {
            Form {
                PocketHeading(eyebrow: "Make yourself at home", title: "Bring an app\nto Pocket.")
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 16, trailing: 0))
                if let error = backend.error { Text(error).foregroundStyle(.red) }
                Section {
                    TextField("App name", text: $name)
                    TextField("https://your-app.com", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Short description", text: $summary, axis: .vertical)
                } footer: { Text("Only you can see this listing until you share it. Your website stays on its existing host.") }
                Button("Add app") {
                    Task { if await backend.register(name: name, url: url, summary: summary) { PocketHaptics.success(); dismiss() } }
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .disabled(name.isEmpty || url.isEmpty)
                if backend.busy { ProgressView("Adding app…") }
            }.pocketList().navigationTitle("Add app").navigationBarTitleDisplayMode(.inline).disabled(backend.busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
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
