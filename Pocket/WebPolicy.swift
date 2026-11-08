import Foundation

/// Shared by restoration and navigation. Never pass arbitrary incoming URLs to WebKit.
enum WebPolicy {
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
    static func restorable(_ url: URL, for entry: URL) -> Bool {
        guard safe(url, for: entry), let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.fragment == nil else { return false }
        let sensitive = ["token", "access_token", "id_token", "code", "password", "secret", "session"]
        return !(c.queryItems ?? []).contains { item in sensitive.contains(item.name.lowercased()) }
    }
}
