import SwiftUI
import MapKit

struct NativeExperienceView: View {
    let app: MiniApp
    @EnvironmentObject private var backend: Backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var recorder = RouteRecorder.shared
    @State private var config: Experience?
    @State private var revision = 0
    @State private var screenID = ""
    @State private var failure: String?
    @State private var consent = false
    @State private var startAction: Experience.Action?
    @State private var dataValues: [String: [String: String]] = [:]
    @State private var history: [LocalRouteSession] = []
    @State private var fetching = false
    @State private var fetchTask: Task<Void, Never>?
    private var scope: RouteScope { RouteScope(server: backend.address, account: backend.username ?? "", experience: app.id) }
    private var ownsRoute: Bool { recorder.scope == scope }
    private var consentKey: String { "pocket.consent." + scope.storageKey }
    var body: some View {
        NavigationStack {
            List {
                if let config {
                    if config.capabilities.contains("route.recording") {
                        Section("Route recording") {
                            Text(ownsRoute ? recorder.status : "Stopped").accessibilityAddTraits(.updatesFrequently)
                            if ownsRoute && recorder.recording { Button("Stop recording", role: .destructive) { recorder.stop() } }
                            Text("Routes stay on this device. Recording can continue while Pocket is in the background, with the system location indicator visible.").font(.caption)
                        }
                    }
                    if let screen = config.screens.first(where: { $0.id == screenID }) {
                        Section(screen.title) {
                            ForEach(Array(screen.components.enumerated()), id: \.offset) { _, component in componentView(component) }
                        }
                    }
                    if ownsRoute, let session = recorder.session {
                        Section("Local session") {
                            Text("\(session.points.count) recorded points")
                            Button("Delete local route data", role: .destructive) { recorder.clear(reason: "Local data deleted") }
                        }
                    }
                    if !history.isEmpty {
                        Section("Saved on this device") {
                            ForEach(history.prefix(20)) { saved in
                                VStack(alignment: .leading) {
                                    Text(saved.started, style: .date)
                                    Text("\(saved.points.count) points · \(saved.stopped == nil ? "Interrupted" : "Finished")").font(.caption)
                                }
                            }
                            Button("Delete saved routes", role: .destructive) {
                                if ownsRoute { recorder.clear(reason: "Local data deleted") }
                                do { try RouteStorage().remove(scope: scope); history = [] }
                                catch { failure = "Could not remove saved routes." }
                            }
                        }
                    }
                    if !consent && !config.capabilities.isEmpty {
                        Button("Review native permissions") { startAction = Experience.Action(type: "consent", activityType: nil, layout: nil, screen: nil, dataSource: nil) }
                    }
                } else if failure == nil { ProgressView("Loading experience…") }
                if let failure { Text(failure).foregroundStyle(.red); Button("Retry") { Task { await reload() } } }
                if ownsRoute, let error = recorder.error { Text(error).foregroundStyle(.red) }
                if fetching { ProgressView("Refreshing data…") }
            }
            .navigationTitle(config?.metadata.name ?? app.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { recorder.stop(); dismiss() } } }
        }
        .task { await reload() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if phase == .active { await reload() }
            }
        }
        .onChange(of: phase) { _, phase in if phase == .active { Task { await reload() } } }
        .onChange(of: recorder.scope) { _, _ in history = (try? RouteStorage().sessions(scope: scope)) ?? [] }
        .onChange(of: recorder.recording) { _, recording in if !recording { history = (try? RouteStorage().sessions(scope: scope)) ?? [] } }
        .onChange(of: backend.username) { _, _ in cancelAndClose() }
        .onChange(of: backend.address) { _, _ in cancelAndClose() }
        .onDisappear { fetchTask?.cancel(); if ownsRoute { recorder.stop() } }
        .alert("Allow native capabilities?", isPresented: Binding(get: { startAction != nil }, set: { if !$0 { startAction = nil } })) {
            Button("Cancel", role: .cancel) { startAction = nil }
            Button("Allow") {
                guard let action = startAction, let config else { return }
                UserDefaults.standard.set(config.capabilities, forKey: consentKey); consent = true; startAction = nil
                if action.type == "route.start" { recorder.start(scope: scope, activityType: action.activityType ?? "walk") }
            }
        } message: {
            Text("\(config?.metadata.name ?? app.name) requests \(config?.capabilities.joined(separator: ", ") ?? ""). Starting a route records your location locally until you stop, close the experience, or access is removed. Live Activities show route progress on your Lock Screen. iOS also asks for location permission.")
        }
    }
    @ViewBuilder private func componentView(_ component: Experience.Component) -> some View {
        switch component.type {
        case "text": Text(component.text ?? "")
        case "metric":
            TimelineView(.periodic(from: .now, by: 1)) { _ in LabeledContent(component.label ?? "", value: metric(component.binding)) }
        case "button": Button(component.label ?? "Action") { if let action = component.action { execute(action) } }.disabled(fetching)
        case "routeMap":
            Map {
                if ownsRoute, let points = recorder.session?.points, !points.isEmpty {
                    MapPolyline(coordinates: points.suffix(5000).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.green, lineWidth: 4)
                }
            }.frame(height: 220).accessibilityLabel("Your locally recorded route")
        default: EmptyView()
        }
    }
    private func metric(_ binding: Experience.Binding?) -> String {
        guard let binding else { return "—" }
        if binding.source == "data" { return dataValues[binding.dataSource ?? ""]?[binding.field] ?? "—" }
        guard ownsRoute else { return binding.field == "status" ? "Stopped" : "0" }
        switch binding.field {
        case "status": return recorder.status
        case "distanceMeters": return String(format: "%.0f", recorder.distance)
        case "elapsedSeconds":
            guard let session = recorder.session else { return "0" }
            return String(Int((session.stopped ?? .now).timeIntervalSince(session.started)))
        default: return "—"
        }
    }
    private func execute(_ action: Experience.Action) {
        guard let config, backend.username != nil else { return }
        switch action.type {
        case "route.start": startAction = action // Every recording starts with a user confirmation.
        case "route.stop": if ownsRoute { recorder.stop() }
        case "liveActivity.start": if consent && ownsRoute { recorder.startActivity(name: config.metadata.name) } else { failure = "Allow capabilities and start a route first." }
        case "liveActivity.stop": if ownsRoute { recorder.stopActivity() }
        case "navigate": screenID = action.screen ?? screenID
        case "data.refresh":
            guard let source = config.dataSources?.first(where: { $0.id == action.dataSource }), !fetching else { return }
            fetching = true; failure = nil
            fetchTask = Task {
                defer { fetching = false }
                do {
                    let values = try await ExperienceData().fetch(source)
                    try Task.checkCancellation(); dataValues[source.id] = values
                } catch { if !Task.isCancelled { dataValues[source.id] = nil; failure = "Data refresh failed: \(error.localizedDescription)" } }
            }
        default: break
        }
    }
    private func reload() async {
        do {
            let (next, version) = try await backend.experience(app.id)
            let allowed = Set(UserDefaults.standard.stringArray(forKey: consentKey) ?? [])
            let approved = Set(next.capabilities).isSubset(of: allowed)
            if ownsRoute && (!approved || Set(config?.capabilities ?? []) != Set(next.capabilities)) { recorder.stop() }
            consent = approved
            if version != revision {
                startAction = nil; fetchTask?.cancel(); dataValues = [:]; config = next; revision = version
                if !next.screens.contains(where: { $0.id == screenID }) { screenID = next.screens[0].id }
            }
            history = (try? RouteStorage().sessions(scope: scope)) ?? []
            failure = nil
        } catch {
            // Fail closed on validation, network failure or observed access revocation.
            if ownsRoute { recorder.stop() }
            config = nil; fetchTask?.cancel(); dataValues = [:]; failure = error.localizedDescription
        }
    }
    private func cancelAndClose() { fetchTask?.cancel(); recorder.clear(reason: "Session changed"); dismiss() }
}
