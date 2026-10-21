import SwiftUI

/// A feature that lives inside the notch. Each module owns its own state and views;
/// the shell only decides where and when those views are shown.
@MainActor
protocol NotchModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }

    /// Main content shown when this module's tab is selected in the expanded panel.
    func makeExpandedView() -> AnyView

    /// Optional compact views drawn beside the hardware notch while collapsed.
    func makeLeftWing() -> AnyView?
    func makeRightWing() -> AnyView?

    /// Called once at launch and before quit.
    func start()
    func stop()

    /// Called when this module's tab becomes visible / hidden in the expanded panel.
    /// Use it to throttle work that is only needed on screen.
    func setVisible(_ visible: Bool)
}

extension NotchModule {
    func makeLeftWing() -> AnyView? { nil }
    func makeRightWing() -> AnyView? { nil }
    func start() {}
    func stop() {}
    func setVisible(_ visible: Bool) {}
}
