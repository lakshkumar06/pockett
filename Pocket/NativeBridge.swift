import CoreMotion
import UIKit
import WebKit

/// A fixed capability allowlist, never a generic Objective-C/Swift invocation channel.
@MainActor final class NativeBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let script = #"""
    (() => {
      if (window !== window.top) return;
      const call = (method, params) => window.webkit.messageHandlers.pocketNative.postMessage(
        params === undefined ? {version: 1, method} : {version: 1, method, params});
      Object.defineProperty(window, 'pocketNative', { configurable: false, writable: false,
        value: Object.freeze({ version: 1,
          capabilities: () => call('capabilities'),
          haptics: Object.freeze({ tap: () => call('haptics.tap') }),
          motion: Object.freeze({ sample: () => call('motion.sample') }),
          pedometer: Object.freeze({ today: () => call('pedometer.today') }),
          location: Object.freeze({ start: () => call('location.start'), read: () => call('location.read'), stop: () => call('location.stop') }),
          widgets: Object.freeze({ update: params => call('widgets.update', params), clear: () => call('widgets.clear') })
        })
      });
    })();
    """#
    let app: MiniApp
    weak var webView: WKWebView?
    var visible = false
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private var grants = Set<String>()
    private var denied = Set<String>()
    private var pendingMethod: String?
    private var widgetInput: (String, String)?
    private var pending: ((Any?, String?) -> Void)?
    private var requestID = UUID()
    private var timeout: Task<Void, Never>?
    private weak var prompt: UIAlertController?
    private var lastCall = Date.distantPast

    init(app: MiniApp) { self.app = app }

    func reset() {
        grants.removeAll(); denied.removeAll()
        prompt?.dismiss(animated: false); prompt = nil
        finish(nil, "cancelled")
    }

    private var active: Bool {
        visible && UIApplication.shared.applicationState == .active && webView?.window != nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard message.webView === webView, let url = webView?.url, active,
              WebPolicy.nativeAccess(entry: app.url, page: url, scheme: origin.protocol,
                                     host: origin.host, port: origin.port, mainFrame: message.frameInfo.isMainFrame) else {
            replyHandler(nil, "untrusted_or_inactive"); return
        }
        guard let body = message.body as? [String: Any], Set(body.keys).isSubset(of: ["version", "method", "params"]),
              let version = body["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let method = body["method"] as? String,
              ["capabilities", "haptics.tap", "motion.sample", "pedometer.today", "location.start", "location.read", "location.stop", "widgets.update", "widgets.clear"].contains(method) else {
            replyHandler(nil, "invalid_request"); return
        }
        var card: (String, String)?
        if method == "widgets.update" {
            guard let params = body["params"] as? [String: Any], Set(params.keys) == ["title", "body"],
                  let title = params["title"] as? String, let text = params["body"] as? String,
                  WidgetCard.valid(title: title, body: text) else { replyHandler(nil, "invalid_request"); return }
            card = (title, text)
        } else if body["params"] != nil { replyHandler(nil, "invalid_request"); return }
        if method == "location.stop" {
            NativeLocation.shared.stop(app: app); replyHandler(["ok": true], nil); return
        }
        if method == "widgets.clear" {
            WidgetPublisher.clearCard(app: app); replyHandler(["ok": true], nil); return
        }
        if method == "capabilities" {
            replyHandler(["version": 1, "haptics": UIDevice.current.userInterfaceIdiom == .phone,
                          "location": true, "backgroundLocation": true, "widgets": true,
                          "motion": motion.isDeviceMotionAvailable, "pedometer": CMPedometer.isStepCountingAvailable()], nil)
            return
        }
        guard pending == nil else { replyHandler(nil, "busy"); return }
        guard Date().timeIntervalSince(lastCall) >= 0.25 else { replyHandler(nil, "rate_limited"); return }
        lastCall = Date()
        guard !denied.contains(method) else { replyHandler(nil, "permission_denied"); return }
        guard (method != "motion.sample" || motion.isDeviceMotionAvailable),
              (method != "pedometer.today" || CMPedometer.isStepCountingAvailable()),
              (method != "haptics.tap" || UIDevice.current.userInterfaceIdiom == .phone) else {
            replyHandler(nil, "unavailable"); return
        }
        pending = replyHandler; pendingMethod = method; widgetInput = card
        let id = UUID(); requestID = id
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.prompt?.dismiss(animated: true); self.prompt = nil
            self.finish(nil, "timeout")
        }
        if method != "location.start", grants.contains(method) { perform(method, id: id); return }
        guard var presenter = webView?.window?.rootViewController else { finish(nil, "unavailable"); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed, !(presenter is UIAlertController) else { finish(nil, "busy"); return }
        let description: String
        switch method {
        case "location.start": description = "record your location, including while the screen is locked"
        case "location.read": description = "read its recorded route"
        case "widgets.update": description = "show content in a Home Screen widget"
        case "motion.sample": description = "read this device’s movement and orientation"
        case "pedometer.today": description = "read your step count and walking distance for today"
        default: description = "play haptic feedback"
        }
        let detail: String
        if method == "location.start" {
            detail = "Recording continues in the background for up to 8 hours. Use Pocket’s Stop control to end it. The latest 1,000 points stay in memory for this app until you sign out or Pocket closes."
        } else if method == "widgets.update" {
            detail = "This text stays visible outside Pocket until replaced or cleared. Add the Pocket app card widget from the Home Screen widget gallery."
        } else { detail = "Access resets when you leave or reload." }
        let alert = UIAlertController(title: "Allow \(app.name) to \(description)?",
                                      message: "\(app.url.host ?? "This website")\n\(detail)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Don’t allow", style: .cancel) { [weak self] _ in
            guard let self, self.requestID == id else { return }
            self.prompt = nil; self.denied.insert(method); self.finish(nil, "permission_denied")
        })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { [weak self] _ in
            guard let self, self.requestID == id else { return }
            self.prompt = nil
            guard self.active else { self.finish(nil, "cancelled"); return }
            self.grants.insert(method); self.perform(method, id: id)
        })
        prompt = alert; presenter.present(alert, animated: true)
    }

    private func perform(_ method: String, id: UUID) {
        guard active, requestID == id else { finish(nil, "cancelled"); return }
        switch method {
        case "location.start":
            NativeLocation.shared.start(app: app) { [weak self] result, error in
                guard let self, self.requestID == id else { return }
                if error == nil { self.grants.insert("location.read") }
                self.finish(result, error)
            }
        case "location.read": finish(NativeLocation.shared.snapshot(app: app), nil)
        case "widgets.update":
            guard let (title, body) = widgetInput, WidgetPublisher.updateCard(app: app, title: title, body: body) else {
                finish(nil, "unavailable"); return
            }
            finish(["ok": true, "requiresUserInstallation": true], nil)
        case "haptics.tap":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            finish(["ok": true], nil)
        case "motion.sample":
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, error in
                Task { @MainActor in
                    guard let self, self.requestID == id else { return }
                    guard let sample, error == nil else { self.finish(nil, "sensor_error"); return }
                    self.finish(["attitude": ["roll": sample.attitude.roll, "pitch": sample.attitude.pitch, "yaw": sample.attitude.yaw],
                                 "gravity": ["x": sample.gravity.x, "y": sample.gravity.y, "z": sample.gravity.z],
                                 "acceleration": ["x": sample.userAcceleration.x, "y": sample.userAcceleration.y, "z": sample.userAcceleration.z]], nil)
                }
            }
        case "pedometer.today":
            let end = Date(), start = Calendar.current.startOfDay(for: Date())
            pedometer.queryPedometerData(from: start, to: end) { [weak self] data, error in
                Task { @MainActor in
                    guard let self, self.requestID == id else { return }
                    guard let data, error == nil else {
                        self.finish(nil, CMPedometer.authorizationStatus() == .denied ? "permission_denied" : "sensor_error"); return
                    }
                    self.finish(["steps": data.numberOfSteps, "distanceMeters": data.distance ?? NSNull(),
                                 "from": start.timeIntervalSince1970 * 1000, "to": end.timeIntervalSince1970 * 1000], nil)
                }
            }
        default: finish(nil, "invalid_request")
        }
    }

    private func finish(_ result: Any?, _ error: String?) {
        motion.stopDeviceMotionUpdates()
        timeout?.cancel(); timeout = nil
        let reply = pending; pending = nil; requestID = UUID()
        let method = pendingMethod; pendingMethod = nil; widgetInput = nil
        if method == "location.start" { NativeLocation.shared.cancelPending(app: app) }
        if error == nil && !active { reply?(nil, "cancelled") }
        else { reply?(result, error) }
    }
}
