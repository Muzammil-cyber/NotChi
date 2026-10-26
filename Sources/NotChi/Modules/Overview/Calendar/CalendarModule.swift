// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Calendar: today's agenda with one-click meeting joins, as a section of the Overview
/// tab, plus a countdown beside the notch from five minutes before an event or reminder.
@MainActor
final class CalendarModule: NotchModule {
    let id = "calendar"
    let title = "Calendar"
    let systemImage = "calendar"

    private let model = CalendarModel.shared
    private let settings = Settings.shared

    var isEnabled: Bool { settings.calendarEnabled }

    /// From 5 minutes before an event or timed reminder: an icon on one side, "12m" on the other.
    var wingClaim: WingClaim? {
        guard settings.calendarEnabled, settings.calendarInWings, model.imminent != nil else { return nil }
        return WingClaim(urgent: model.imminentIsUrgent, width: 40)
    }

    func makeExpandedView() -> AnyView { AnyView(CalendarExpandedView(model: model)) }
    func makeLeftWing() -> AnyView? { AnyView(CalendarLeftWing(model: model)) }
    func makeRightWing() -> AnyView? { AnyView(CalendarRightWing(model: model)) }

    func start() { observeEnabled() }
    func stop() { model.setRunning(false) }

    /// Re-checks access when shown: the user may have granted it in System Settings.
    func setVisible(_ visible: Bool) {
        if visible { model.reload() }
    }

    private func observeEnabled() {
        withObservationTracking {
            model.setRunning(settings.calendarEnabled)
            _ = settings.hiddenCalendarIDs
            _ = settings.showReminders
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.model.reload()
                self?.observeEnabled()
            }
        }
    }
}
