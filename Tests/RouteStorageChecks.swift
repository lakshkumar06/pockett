import Foundation

@main struct RouteStorageChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RouteStorage(root: root)
        let scope = RouteScope(server: "https://pocket.example", account: "alice", experience: "one")
        let session = LocalRouteSession(id: UUID(), started: .now, stopped: .now, points: [RoutePoint(latitude: 1, longitude: 2, timestamp: .now)])
        try store.save(session, scope: scope)
        let saved = try store.sessions(scope: scope)
        assert(saved.first?.points == session.points)
        for other in [RouteScope(server: scope.server, account: "bob", experience: "one"), RouteScope(server: scope.server, account: "alice", experience: "two"), RouteScope(server: "https://other.example", account: "alice", experience: "one")] {
            let isolated = try store.sessions(scope: other)
            assert(isolated.isEmpty)
        }
        try store.remove(scope: scope)
        let removed = try store.sessions(scope: scope)
        assert(removed.isEmpty)
        let second = RouteScope(server: scope.server, account: scope.account, experience: "two")
        let otherAccount = RouteScope(server: scope.server, account: "bob", experience: "two")
        try store.save(session, scope: scope); try store.save(session, scope: second); try store.save(session, scope: otherAccount)
        try store.removeAccount(scope: scope)
        let firstCleared = try store.sessions(scope: scope), secondCleared = try store.sessions(scope: second), otherPreserved = try store.sessions(scope: otherAccount)
        assert(firstCleared.isEmpty && secondCleared.isEmpty && otherPreserved.count == 1)
        print("Route storage isolation and account cleanup checks passed")
    }
}
