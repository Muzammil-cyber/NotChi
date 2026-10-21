import Observation
import SwiftUI

/// Shared UI state for the notch. The window controller is the only writer of
/// `isExpanded`; views and modules read it and call `NotchController` to change it.
@MainActor
@Observable
final class NotchState {
    static let shared = NotchState()

    var isExpanded = false
    var geometry: NotchGeometry
    var selectedModuleID: String = ""

    /// Reasons the panel must not auto-collapse (e.g. a drag in progress, a text field
    /// being edited, a confirmation dialog). Modules insert and remove their own keys.
    var holdOpenReasons: Set<String> = []

    private init() {
        geometry = NotchGeometry.preferredScreen().map(NotchGeometry.init(screen:))
            ?? NotchGeometry(fallbackFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    func holdOpen(_ reason: String, _ hold: Bool) {
        if hold { holdOpenReasons.insert(reason) } else { holdOpenReasons.remove(reason) }
    }
}

extension NotchGeometry {
    init(fallbackFrame: CGRect) {
        screenFrame = fallbackFrame
        hasNotch = false
        notchSize = CGSize(width: 190, height: 24)
    }
}
