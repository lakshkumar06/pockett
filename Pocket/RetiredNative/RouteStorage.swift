import Foundation
import CryptoKit

/// Private application storage, never the App Group or creator backend.
struct RoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

struct LocalRouteSession: Codable, Identifiable {
    let id: UUID
    let started: Date
    var stopped: Date?
    var points: [RoutePoint]
}

struct RouteScope: Equatable {
    let server: String
    let account: String
    let experience: String
    var accountKey: String {
        let data = try! JSONEncoder().encode([server, account])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var storageKey: String {
        let data = try! JSONEncoder().encode([server, account, experience])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct RouteStorage {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PocketRoutes", isDirectory: true)
    }
    private func directory(_ scope: RouteScope) -> URL { root.appendingPathComponent(scope.accountKey, isDirectory: true).appendingPathComponent(scope.storageKey, isDirectory: true) }
    func save(_ session: LocalRouteSession, scope: RouteScope) throws {
        guard session.points.count <= 100_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        let folder = directory(scope)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let data = try JSONEncoder().encode(session)
        try data.write(to: folder.appendingPathComponent(session.id.uuidString + ".json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    func sessions(scope: RouteScope) throws -> [LocalRouteSession] {
        let folder = directory(scope)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(LocalRouteSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.started > $1.started }
    }
    func removeAccount(scope: RouteScope) throws {
        let folder = root.appendingPathComponent(scope.accountKey, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
    func remove(scope: RouteScope) throws {
        let folder = directory(scope)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}
