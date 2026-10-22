import AppKit
import UserNotifications

/// Notification Center alerts for phone transfers: an incoming share (with its PIN and
/// Accept / Decline buttons) and finished transfers. The notch shows the same request, so
/// whichever the user answers first wins and the other is cleared.
@MainActor
final class TransferNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onAccept: ((UUID) -> Void)?
    var onDecline: ((UUID) -> Void)?
    var onOpen: ((UUID) -> Void)?

    private static let requestCategory = "notchi.transfer.request"
    private static let finishedCategory = "notchi.transfer.finished"
    private static let acceptAction = "accept"
    private static let declineAction = "decline"

    /// Notification Center needs a real app bundle; `swift run` builds have none.
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    private var authorizationRequested = false

    override init() {
        super.init()
        guard let center else { return }
        center.delegate = self
        let accept = UNNotificationAction(identifier: Self.acceptAction, title: "Accept", options: [])
        let decline = UNNotificationAction(identifier: Self.declineAction, title: "Decline", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.requestCategory, actions: [accept, decline], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.finishedCategory, actions: [], intentIdentifiers: []),
        ])
    }

    /// Asks for permission once, the first time phone transfer is turned on. Asynchronous:
    /// the system prompt never blocks the notch.
    func requestAuthorizationIfNeeded() {
        guard let center, !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("NotChi: notification permission error: %@", error.localizedDescription) }
        }
    }

    /// Posts the share request. `shown` reports whether a banner can actually appear
    /// (notifications on in Settings and allowed by macOS), so the caller can fall back to
    /// expanding the notch.
    func notifyIncoming(_ id: UUID, from device: String, summary: String, size: Int64, pin: String,
                        shown: @escaping @MainActor (Bool) -> Void) {
        guard let center, Settings.shared.transferNotifications else { shown(false); return }
        let content = UNMutableNotificationContent()
        content.title = "\(device) wants to share"
        content.body = "\(summary) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))\nPIN \(pin)"
        content.categoryIdentifier = Self.requestCategory
        content.sound = .default
        center.getNotificationSettings { settings in
            let visible = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
            Task { @MainActor in shown(visible) }
        }
        post(id, content)
    }

    func notifyFinished(_ id: UUID, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.finishedCategory
        post(id, content)
    }

    func remove(_ id: UUID) {
        center?.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        center?.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    private func post(_ id: UUID, _ content: UNMutableNotificationContent) {
        guard let center, Settings.shared.transferNotifications else { return }
        center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while NotChi is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let id = UUID(uuidString: response.notification.request.identifier)
        Task { @MainActor [weak self] in
            if let id, let self {
                switch action {
                case Self.acceptAction: self.onAccept?(id)
                case Self.declineAction: self.onDecline?(id)
                default: self.onOpen?(id)
                }
            }
            completionHandler()
        }
    }
}
