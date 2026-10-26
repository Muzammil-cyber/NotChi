// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import EventKit
import SwiftUI

// Value types copied out of EventKit: what the agenda, reminders and wings display.

/// One event in today's agenda, copied out of EventKit so views never touch EKEvent.
struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let meeting: MeetingLink?
    /// Has other attendees: a meeting rather than a personal reminder block.
    let hasAttendees: Bool

    var isMeeting: Bool { meeting != nil || hasAttendees }
}

/// An open reminder due today or overdue, copied out of EventKit.
struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    /// The due date has a time of day (not just a day).
    let hasTime: Bool
    let color: Color

    init(id: String, title: String, due: Date?, hasTime: Bool, color: Color) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.color = color
    }

    /// Copies what the agenda needs. Kept out of closures with explicit types: inline, the
    /// expression is too much for some Swift versions' type checker.
    init(reminder: EKReminder) {
        let components: DateComponents? = reminder.dueDateComponents
        let title: String = reminder.title ?? ""
        let cgColor: CGColor = reminder.calendar?.cgColor ?? NSColor.systemOrange.cgColor
        self.init(id: reminder.calendarItemIdentifier,
                  title: title.isEmpty ? "Untitled" : title,
                  due: components.flatMap { Calendar.current.date(from: $0) },
                  hasTime: components?.hour != nil,
                  color: Color(cgColor: cgColor))
    }

    /// Earliest due first (undated last), then by title.
    static func dueOrder(_ a: ReminderItem, _ b: ReminderItem) -> Bool {
        let aDue = a.due ?? .distantFuture
        let bDue = b.due ?? .distantFuture
        return aDue != bDue ? aDue < bDue : a.title < b.title
    }

    func isOverdue(now: Date) -> Bool {
        guard let due else { return false }
        return hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }
}

/// Something worth a countdown beside the notch: a timed event or a reminder with a due time.
struct WingItem: Equatable {
    enum Kind: Equatable { case meeting, event, reminder }

    let kind: Kind
    let title: String
    let start: Date
    /// When it stops claiming the wings: a minute after the start, long enough to read "now".
    let end: Date
    let color: Color
}
