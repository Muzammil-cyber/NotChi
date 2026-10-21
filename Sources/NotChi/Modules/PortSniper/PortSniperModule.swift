import SwiftUI

/// Lists local listening TCP ports with health, and lets you open, reveal or kill them.
@MainActor
final class PortSniperModule: NotchModule {
    let id = "ports"
    let title = "Ports"
    let systemImage = "network"

    private let model = PortModel()

    init() {}

    func makeExpandedView() -> AnyView { AnyView(PortSniperView(model: model)) }

    func setVisible(_ visible: Bool) { model.setVisible(visible) }
    func stop() { model.setVisible(false) }
}
