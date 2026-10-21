import AppKit
import ApplicationServices
import Observation

enum Permissions {
    /// Whether NotChi may post synthetic key events (needed for auto-paste).
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that deep-links to Privacy & Security → Accessibility.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Live Accessibility trust state. macOS posts `com.apple.accessibility.api` when any app's
/// grant changes; a slow poll backs that up, since the notification is not guaranteed.
@MainActor
@Observable
final class AccessibilityStatus {
    static let shared = AccessibilityStatus()

    private(set) var isTrusted = Permissions.isAccessibilityTrusted
    @ObservationIgnored private var timer: Timer?

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            // The new value lands a moment after the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { AccessibilityStatus.shared.refresh() }
            }
        }
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { AccessibilityStatus.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != isTrusted { isTrusted = trusted }
    }
}
