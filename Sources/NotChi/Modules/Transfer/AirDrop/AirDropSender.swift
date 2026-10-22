import AppKit

/// Sends files to an iPhone through the system AirDrop sheet.
@MainActor
enum AirDropSender {
    static var isAvailable: Bool { NSSharingService(named: .sendViaAirDrop) != nil }

    /// Shows the AirDrop picker for `urls`. macOS owns the rest of the flow (device choice,
    /// progress, errors), so there is nothing to track afterwards.
    @discardableResult
    static func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return false }
        NotchController.shared.collapse()
        // The picker is a window of ours; it needs the app active to come to the front.
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }
}
