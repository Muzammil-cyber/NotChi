// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Left wing: what's coming, as an icon in its color — a camera for a call, a calendar for
/// any other event, a checklist for a reminder.
struct CalendarLeftWing: View {
    let model: CalendarModel

    var body: some View {
        Group {
            if let item = model.imminent {
                Image(systemName: Self.symbol(for: item.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.kind == .meeting ? Color.green : item.color)
                    .help(item.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func symbol(for kind: WingItem.Kind) -> String {
        switch kind {
        case .meeting: "video.fill"
        case .event: "calendar"
        case .reminder: "checklist"
        }
    }
}

/// Right wing: the countdown ("4m", then "now"). Ticks once a minute, only while shown.
struct CalendarRightWing: View {
    let model: CalendarModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let item = model.imminent {
                Text(Self.countdown(to: item.start, now: context.date))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func countdown(to start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes > 0 ? "\(minutes)m" : "now"
    }
}
