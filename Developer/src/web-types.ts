/** Listing metadata only. The creator owns the website and all of its UI. */
export interface Appearance { colorScheme?: 'system' | 'light' | 'dark'; themeColor?: string }
export interface WebManifest {
  schemaVersion: 'web-v1'; creatorKey: string; name: string; summary: string;
  entryURL: string; iconURL: string; version: string; appearance?: Appearance;
}
export interface NotificationEvent {
  idempotencyKey: string; subscriptionId: string; title: string; body: string; target: string;
}
export interface Subscription {subscriptionId: string; appId: string; notificationsEnabled: boolean}
export interface EventReceipt {eventId: string; duplicate: boolean}
export interface Registration {appId: string; revision: number; deepLink: string}
