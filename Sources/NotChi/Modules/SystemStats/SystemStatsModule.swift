import SwiftUI

/// Live CPU, memory and network stats: compact readouts in the wings, detailed cards when expanded.
@MainActor
final class SystemStatsModule: NotchModule {
    let id = "stats"
    let title = "Stats"
    let systemImage = "gauge.with.dots.needle.33percent"

    private let model = StatsModel()

    func makeExpandedView() -> AnyView { AnyView(StatsExpandedView(model: model)) }
    func makeLeftWing() -> AnyView? { AnyView(StatsLeftWing(model: model)) }
    func makeRightWing() -> AnyView? { AnyView(StatsRightWing(model: model)) }

    func start() { model.begin() }
    func stop() { model.shutdown() }
    func setVisible(_ visible: Bool) { model.setTabVisible(visible) }
}
