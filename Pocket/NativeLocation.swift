import CoreLocation
import SwiftUI

/// One explicitly started recording. WebKit may suspend; Core Location owns collection.
@MainActor final class NativeLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = NativeLocation()
    @Published private(set) var recording = false
    @Published private(set) var appName = ""
    private let manager = CLLocationManager()
    private var owner: String?
    private var started: Date?
    private var points: [[String: Double]] = []
    private var pending: (MiniApp, (Any?, String?) -> Void)?
    private var limit: Task<Void, Never>?
    private var status = "stopped"
    private static func key(_ app: MiniApp) -> String { app.id + "|" + (WebPolicy.origin(app.url) ?? "") }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start(app: MiniApp, reply: @escaping (Any?, String?) -> Void) {
        guard !recording, pending == nil else { reply(nil, "recording_busy"); return }
        pending = (app, reply)
        authorize()
    }
    private func authorize() {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard UIApplication.shared.applicationState == .active else { cancelPending(); return }
            guard let (app, reply) = pending else { return }
            pending = nil
            owner = Self.key(app); appName = app.name; points = []; started = Date()
            recording = true; status = "recording"
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
            limit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8 * 3600))
                guard !Task.isCancelled else { return }
                self?.stop(reason: "time_limit")
            }
            reply(["recording": true], nil)
        default:
            let callback = pending?.1; pending = nil
            callback?(nil, "permission_denied")
        }
    }
    func cancelPending(app: MiniApp) {
        if let pending, Self.key(pending.0) == Self.key(app) { cancelPending() }
    }
    private func cancelPending() {
        let callback = pending?.1; pending = nil
        callback?(nil, "cancelled")
    }
    func stop(reason: String = "stopped") {
        cancelPending()
        manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false
        limit?.cancel(); limit = nil; recording = false; status = reason
    }
    func clear() { stop(); owner = nil; points = []; started = nil; appName = "" }
    func retain(_ ids: Set<String>) {
        if let owner, !ids.contains(String(owner.split(separator: "|", maxSplits: 1)[0])) { clear() }
    }
    func stop(app: MiniApp) {
        cancelPending(app: app)
        if owner == Self.key(app) { stop() }
    }
    func remove(id: String) {
        if owner?.hasPrefix(id + "|") == true || pending?.0.id == id { clear() }
    }
    func snapshot(app: MiniApp) -> [String: Any] {
        guard owner == Self.key(app) else { return ["recording": false, "status": "idle", "points": []] }
        return ["recording": recording, "status": status, "points": points,
                "accuracy": manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced"]
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            let callback = pending?.1; pending = nil
            stop(reason: "permission_denied"); points = []
            callback?(nil, "permission_denied")
        } else { authorize() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording, let started else { return }
        guard Date().timeIntervalSince(started) < 8 * 3600 else { stop(reason: "time_limit"); return }
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.timestamp >= started,
                  abs(location.timestamp.timeIntervalSinceNow) < 30,
                  CLLocationCoordinate2DIsValid(location.coordinate) else { continue }
            let time = location.timestamp.timeIntervalSince1970 * 1000
            guard time > (points.last?["timestamp"] ?? 0) else { continue }
            status = "recording"
            points.append(["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
                           "accuracyMeters": location.horizontalAccuracy, "timestamp": time])
        }
        if points.count > 1000 { points.removeFirst(points.count - 1000) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { stop(reason: "permission_denied"); points = [] }
        else { status = "waiting_for_fix" }
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { stop(reason: "paused_by_system") }
}

struct NativeRecordingControl: View {
    @ObservedObject private var location = NativeLocation.shared
    var body: some View {
        if location.recording {
            HStack {
                Label("\(location.appName) · Recording location", systemImage: "location.fill").font(.caption)
                Spacer()
                Button("Stop", role: .destructive) { location.stop() }.font(.headline)
            }
            .padding(12).background(.regularMaterial)
        }
    }
}
