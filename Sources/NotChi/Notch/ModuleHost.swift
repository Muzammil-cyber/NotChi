import SwiftUI

/// The set of modules shown in the notch, plus the optional stash strip on top.
@MainActor
final class ModuleHost {
    let modules: [NotchModule]
    /// Persistent drop target pinned to the top of the expanded panel.
    let topAccessory: AnyView?

    init(modules: [NotchModule], topAccessory: AnyView?) {
        self.modules = modules
        self.topAccessory = topAccessory
    }

    var hasWings: Bool { leftWing != nil || rightWing != nil }

    private(set) lazy var leftWing: AnyView? = modules.lazy.compactMap { $0.makeLeftWing() }.first
    private(set) lazy var rightWing: AnyView? = modules.lazy.compactMap { $0.makeRightWing() }.first
    private var expandedViews: [String: AnyView] = [:]

    func expandedView(for id: String) -> AnyView {
        if let view = expandedViews[id] { return view }
        let view = modules.first { $0.id == id }?.makeExpandedView() ?? AnyView(EmptyView())
        expandedViews[id] = view
        return view
    }

    func startAll() { modules.forEach { $0.start() } }
    func stopAll() { modules.forEach { $0.stop() } }

    func visibilityChanged(expanded: Bool, selected: String) {
        for module in modules {
            module.setVisible(expanded && module.id == selected)
        }
    }
}
