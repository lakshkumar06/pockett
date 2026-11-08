import Foundation

/// Shared by restoration and navigation. Never pass arbitrary incoming URLs to WebKit.
enum WebPolicy {
    /// Only transfer requests, never remotely supplied transaction-request URLs.
    static func solanaPayment(_ url: URL) -> Bool {
        guard url.absoluteString.count <= 1024,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "solana", c.host == nil, c.fragment == nil,
              c.path.range(of: "^[1-9A-HJ-NP-Za-km-z]{32,44}$", options: .regularExpression) != nil,
              let items = c.queryItems, Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ ["amount", "label"].contains($0.name) }),
              let amount = items.first(where: { $0.name == "amount" })?.value,
              amount.range(of: "^(0|[1-9][0-9]{0,8})(\\.[0-9]{1,9})?$", options: .regularExpression) != nil,
              amount.contains(where: { "123456789".contains($0) }) else { return false }
        return true
    }
    static func origin(_ url: URL) -> String? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = c.host?.lowercased(), !host.isEmpty,
              c.user == nil, c.password == nil, url.absoluteString.count <= 2048,
              !url.absoluteString.contains("\\"), !url.absoluteString.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { return nil }
        return "\(scheme)://\(host):\(c.port ?? (scheme == "https" ? 443 : 80))"
    }
    static func safe(_ url: URL, for entry: URL) -> Bool {
        guard let origin = origin(entry) else { return false }
        return self.origin(url) == origin
    }
    /// Native access is stricter than browsing: HTTPS, exact origin, main frame only.
    static func nativeAccess(entry: URL, page: URL, scheme: String, host: String, port: Int, mainFrame: Bool) -> Bool {
        guard mainFrame, scheme == "https", entry.scheme == "https", safe(page, for: entry),
              let components = URLComponents(url: entry, resolvingAgainstBaseURL: false) else { return false }
        return components.host?.lowercased() == host.lowercased() && (components.port ?? 443) == (port == 0 ? 443 : port)
    }
    static func restorable(_ url: URL, for entry: URL) -> Bool {
        guard safe(url, for: entry), let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.fragment == nil else { return false }
        let sensitive = ["token", "access_token", "id_token", "code", "password", "secret", "session"]
        return !(c.queryItems ?? []).contains { item in sensitive.contains(item.name.lowercased()) }
    }
}
