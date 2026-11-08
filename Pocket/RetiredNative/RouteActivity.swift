import ActivityKit
import Foundation

struct RouteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let distanceMeters: Double
        let started: Date
        let recording: Bool
    }
    let appId: String
    let name: String
}
