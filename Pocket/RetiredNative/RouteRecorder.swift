import SwiftUI
import CoreLocation
import ActivityKit

@MainActor final class RouteRecorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = RouteRecorder()
    @Published private(set) var session: LocalRouteSession?
    @Published private(set) var scope: RouteScope?
    @Published private(set) var distance = 0.0
    @Published private(set) var status = "Stopped"
    @Published var error: String?
    var recording: Bool { session != nil && session?.stopped == nil }
    private let manager = CLLocationManager()
    private let storage = RouteStorage()
    private var pending: (RouteScope, String)?
    private var activity: Activity<RouteActivityAttributes>?
    private var timeout: Task<Void, Never>?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
        // No automatic resumption. End stale activities after process termination.
        Task { for existing in Activity<RouteActivityAttributes>.activities { await existing.end(nil, dismissalPolicy: .immediate) } }
    }
    /// Called only after Pocket's explicit user confirmation, never by fetched data.
    func start(scope: RouteScope, activityType: String) {
        stop()
        pending = (scope, activityType)
        switch manager.authorizationStatus {
        case .notDetermined: status = "Waiting for permission"; manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: begin()
        default: pending = nil; status = "Location permission required"
        }
    }
    private func begin() {
        guard let (scope, activityType) = pending else { return }
        pending = nil; self.scope = scope; distance = 0
        session = LocalRouteSession(id: UUID(), started: .now, stopped: nil, points: [])
        manager.activityType = activityType == "cycle" ? .otherNavigation : .fitness
        manager.allowsBackgroundLocationUpdates = true
        status = "Recording"; error = nil
        persist()
        guard recording else { return }
        manager.startUpdatingLocation()
        timeout = Task {
            try? await Task.sleep(for: .seconds(8 * 3600))
            guard !Task.isCancelled else { return }
            stop(); status = "Stopped at the 8-hour limit"
        }
    }
    func stop() {
        pending = nil; timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false
        if recording { session?.stopped = .now; persist() }
        status = "Stopped"; stopActivity()
    }
    func clear(reason: String) {
        let previous = scope
        if let previous { UserDefaults.standard.removeObject(forKey: "pocket.consent." + previous.storageKey) }
        stop()
        if let previous { do { try storage.remove(scope: previous) } catch { self.error = "Could not remove saved route data." } }
        session = nil; scope = nil; distance = 0; status = reason
    }
    func clearAccount(server: String, account: String) {
        clear(reason: "Session changed")
        do { try storage.removeAccount(scope: RouteScope(server: server, account: account, experience: "")) }
        catch { self.error = "Could not remove saved route data." }
    }
    func revoke(scope revoked: RouteScope) {
        if scope == revoked { clear(reason: "Access removed") }
        UserDefaults.standard.removeObject(forKey: "pocket.consent." + revoked.storageKey)
        do { try storage.remove(scope: revoked) } catch { self.error = "Could not remove revoked route data." }
    }
    private func persist() {
        guard let session, let scope else { return }
        do { try storage.save(session, scope: scope) }
        catch {
            manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false
            self.session?.stopped = .now; status = "Storage unavailable"; self.error = "Recording stopped because the route could not be saved."
            stopActivity()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: begin()
        case .denied, .restricted: clear(reason: "Location permission removed")
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100 && abs(location.timestamp.timeIntervalSinceNow) < 30 {
            guard CLLocationCoordinate2DIsValid(location.coordinate), let current = session else { continue }
            if current.points.count >= 100_000 { stop(); return }
            if let previous = current.points.last {
                guard location.timestamp > previous.timestamp else { continue }
                distance += location.distance(from: CLLocation(latitude: previous.latitude, longitude: previous.longitude))
            }
            session?.points.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timestamp: location.timestamp))
        }
        persist(); updateActivity()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { clear(reason: "Location unavailable") }
        else { self.error = "Waiting for a location fix." }
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { stop(); status = "Stopped when location updates paused" }
    func startActivity(name: String) {
        guard recording, let scope, let session else { error = "Start a route first."; return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { error = "Live Activities are unavailable or disabled."; return }
        guard activity == nil else { return }
        do {
            activity = try Activity.request(attributes: RouteActivityAttributes(appId: scope.experience, name: name), content: ActivityContent(state: .init(distanceMeters: distance, started: session.started, recording: true), staleDate: .now.addingTimeInterval(60)), pushType: nil)
        } catch { self.error = "Could not start the Live Activity." }
    }
    private func updateActivity() {
        guard let activity, let session else { return }
        let content = ActivityContent(state: RouteActivityAttributes.ContentState(distanceMeters: distance, started: session.started, recording: recording), staleDate: .now.addingTimeInterval(60))
        Task { await activity.update(content) }
    }
    func stopActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
