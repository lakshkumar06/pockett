import Foundation

struct WebManifest: Codable, Hashable {
    struct Appearance: Codable, Hashable { let colorScheme: String?; let themeColor: String? }
    let schemaVersion: String
    let creatorKey: String
    let name: String
    let summary: String
    let entryURL: URL
    let iconURL: URL
    let version: String
    let appearance: Appearance?
}
struct InboxEntry: Codable, Identifiable, Hashable {
    let eventId: String; let appId: String; let title: String; let body: String; let target: String
    let createdAt: Double; var read: Bool
    var id: String { eventId }
}
struct InboxReply: Decodable { let entries: [InboxEntry]; let nextCursor: String?; let unreadCount: Int }
struct NotificationSubscription: Codable, Identifiable {
    let subscriptionId: String; let appId: String; var notificationsEnabled: Bool
    var id: String { subscriptionId }
}
struct SubscriptionReply: Decodable { let subscriptions: [NotificationSubscription] }
struct PairingReply: Decodable { let pairingCode: String; let expiresAt: Double }
struct NotificationLaunch: Decodable { let appId: String; let target: String; let url: URL; let deepLink: URL }
struct DeviceReply: Decodable { let ok: Bool; let deliveryMode: String }
struct AppLaunch: Identifiable { let id = UUID(); let app: MiniApp; let exactTarget: URL? }
