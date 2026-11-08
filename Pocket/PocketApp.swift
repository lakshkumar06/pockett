import SwiftUI

@main struct PocketApp: App {
    @UIApplicationDelegateAdaptor(PocketAppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @StateObject private var backend = Backend()
    var body: some Scene {
        WindowGroup {
            SessionView()
                .environmentObject(store)
                .environmentObject(backend)
                .tint(PocketStyle.accent)
                .font(.pocketBody)
                .preferredColorScheme(.dark)
        }
    }
}

/// Keep the app's tabs behind an authenticated session.
struct SessionView: View {
    @EnvironmentObject private var backend: Backend
    @Environment(\.scenePhase) private var scenePhase
    @State private var restoring = true
    @ObservedObject private var notifications = PocketNotifications.shared

    var body: some View {
        Group {
            if restoring {
                ProgressView("Opening Pocket…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PocketStyle.canvas).foregroundStyle(PocketStyle.ink)
            } else if backend.username != nil {
                RootView().environmentObject(backend.home).id(backend.identity)
            } else {
                NavigationStack { AccountView() }
            }
        }
        .onOpenURL { backend.pendingURL = $0 }
        .onChange(of: notifications.pendingURL) { _, url in if let url { backend.pendingURL = url; notifications.pendingURL = nil } }
        .onChange(of: notifications.token) { _, token in
            if let token { Task { await backend.registerDevice(token: token, environment: notifications.environment) } }
        }
        .task {
            if let url = notifications.pendingURL { backend.pendingURL = url; notifications.pendingURL = nil }
            await backend.restore()
            restoring = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !restoring {
                Task { await backend.refresh() }
            }
        }
    }
}
