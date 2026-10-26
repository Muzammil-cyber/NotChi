// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import EventKit
import Observation
import SwiftUI

/// Today's events from the user's calendars. Reloads only when EventKit reports a change,
/// the day rolls over, or the Mac wakes; a single one-shot timer handles the next
/// "meeting soon / started / ended" moment, so nothing polls.
@MainActor
@Observable
final class CalendarModel {
    static let shared = CalendarModel()

    enum Access { case notDetermined, granted, denied }

    /// How long before a meeting it takes over the wings.
    static let leadTime: TimeInterval = 5 * 60
    /// How long an event or reminder shows "now" once it's started.
    static let nowTime: TimeInterval = 60

    private(set) var access: Access = CalendarModel.currentAccess()
    private(set) var reminderAccess: Access = CalendarModel.currentReminderAccess()
    private(set) var events: [AgendaEvent] = []
    /// Open reminders due today or earlier, overdue first.
    private(set) var reminders: [ReminderItem] = []
    /// Reminders just ticked: shown checked for a moment before they leave the list.
    private(set) var completingIDs: Set<String> = []
    /// Tomorrow's first event, shown when today has nothing left.
    private(set) var tomorrowFirst: AgendaEvent?
    /// What to surface beside the notch: an event or reminder starting within `leadTime`,
    /// or one still in its window (see `WingItem.end`).
    private(set) var imminent: WingItem?
    /// True until a few minutes after `imminent` starts; it may then take room from menus.
    private(set) var imminentIsUrgent = false

    var timedEvents: [AgendaEvent] { events.filter { !$0.isAllDay } }
    var allDayEvents: [AgendaEvent] { events.filter(\.isAllDay) }

    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var boundaryTimer: Timer?

    private init() {}

    private static func currentReminderAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    // MARK: Lifecycle

    func setRunning(_ run: Bool) {
        guard run != running else { return }
        running = run
        if run {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                    MainActor.assumeIsolated { CalendarModel.shared.reload() }
                },
                center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { CalendarModel.shared.reload() }
                },
                NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { CalendarModel.shared.reload() }
                },
            ]
            reload()
        } else {
            observers.forEach {
                NotificationCenter.default.removeObserver($0)
                NSWorkspace.shared.notificationCenter.removeObserver($0)
            }
            observers = []
            boundaryTimer?.invalidate()
            boundaryTimer = nil
            events = []
            reminders = []
            tomorrowFirst = nil
            imminent = nil
            imminentIsUrgent = false
        }
    }

    /// Shows the system prompts (calendars, then reminders when shown). Only called from
    /// a button, never at launch.
    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = Self.currentAccess()
            if Settings.shared.showReminders, reminderAccess == .notDetermined {
                _ = try? await store.requestFullAccessToReminders()
                reminderAccess = Self.currentReminderAccess()
            }
            store.reset()
            reload()
        }
    }

    func requestReminderAccess() {
        Task {
            _ = try? await store.requestFullAccessToReminders()
            reminderAccess = Self.currentReminderAccess()
            store.reset()
            reload()
        }
    }

    func openRemindersPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ticks a reminder off in Reminders. It stays visible, checked, for a moment so the
    /// tap reads as done, then leaves the list.
    func complete(_ item: ReminderItem) {
        guard !completingIDs.contains(item.id),
              let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        completingIDs.insert(item.id)
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            completingIDs.remove(item.id)
            NSLog("NotChi: couldn't complete reminder: %@", error.localizedDescription)
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.25)) {
                reminders.removeAll { $0.id == item.id }
            }
            completingIDs.remove(item.id)
            updateImminent()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The user's event calendars, for the Settings picker.
    func calendars() -> [EKCalendar] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event).sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
    }

    // MARK: Loading

    func reload() {
        let newAccess = Self.currentAccess()
        if access != newAccess { access = newAccess }
        let newReminderAccess = Self.currentReminderAccess()
        if reminderAccess != newReminderAccess { reminderAccess = newReminderAccess }
        guard running else { return }
        loadReminders()
        guard access == .granted else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let hidden = Set(Settings.shared.hiddenCalendarIDs)
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            events = []
            tomorrowFirst = nil
            updateImminent()
            return
        }
        let loaded = loadEvents(from: dayStart, to: dayEnd, calendars: calendars)
        if events != loaded { events = loaded }
        let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: dayEnd)!
        let tomorrow = loadEvents(from: dayEnd, to: tomorrowEnd, calendars: calendars).first { !$0.isAllDay }
        if tomorrowFirst != tomorrow { tomorrowFirst = tomorrow }
        updateImminent()
    }

    private func loadEvents(from start: Date, to end: Date, calendars: [EKCalendar]) -> [AgendaEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.declined($0) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                AgendaEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "@\(event.startDate.timeIntervalSince1970)",
                    title: event.title?.isEmpty == false ? event.title : "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: Color(cgColor: event.calendar.cgColor ?? NSColor.systemBlue.cgColor),
                    location: event.location?.isEmpty == false ? event.location : nil,
                    meeting: MeetingLinkDetector.link(in: event),
                    hasAttendees: (event.attendees?.count ?? 0) > 1
                )
            }
    }

    /// Open reminders due by the end of today (overdue included). EventKit answers
    /// asynchronously; results are copied into value types before hopping to the main actor.
    private func loadReminders() {
        guard Settings.shared.showReminders, reminderAccess == .granted else {
            if !reminders.isEmpty { reminders = [] }
            return
        }
        let calendar = Calendar.current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: dayEnd, calendars: nil)
        store.fetchReminders(matching: predicate) { found in
            let items = (found ?? []).map(ReminderItem.init(reminder:))
            Task { @MainActor in
                let model = CalendarModel.shared
                // Keep just-ticked items until their checkmark has been seen.
                let pending = model.reminders.filter { model.completingIDs.contains($0.id) }
                let merged = items.filter { !model.completingIDs.contains($0.id) } + pending
                let sorted = merged.sorted(by: ReminderItem.dueOrder)
                if model.reminders != sorted {
                    model.reminders = sorted
                    model.updateImminent()
                }
            }
        }
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    /// Recomputes the wing state, then sleeps until the next moment it could change.
    private func updateImminent() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        let now = Date()
        let items = wingItems()
        // Prefer one about to start over one already running (back-to-back meetings).
        let soon = items.filter { $0.start > now && $0.start.timeIntervalSince(now) <= Self.leadTime }
            .min { $0.start < $1.start }
        let current = items.filter { $0.start <= now && $0.end > now }.max { $0.start < $1.start }
        let next = soon ?? current
        if imminent != next { imminent = next }
        let urgent = next.map { now < $0.start.addingTimeInterval(Self.leadTime) } ?? false
        if imminentIsUrgent != urgent { imminentIsUrgent = urgent }

        let boundaries = items.flatMap {
            [$0.start.addingTimeInterval(-Self.leadTime), $0.start, $0.start.addingTimeInterval(Self.leadTime), $0.end]
        }
        guard let wake = boundaries.filter({ $0 > now }).min() else { return }
        let timer = Timer(fire: wake.addingTimeInterval(0.5), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { CalendarModel.shared.updateImminent() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    /// Timed events, plus reminders due at a time today (not overdue ones: they'd hold the
    /// wings all day).
    private func wingItems() -> [WingItem] {
        let events = timedEvents.map { event in
            WingItem(kind: event.isMeeting ? .meeting : .event, title: event.title, start: event.start,
                     end: min(event.end, event.start.addingTimeInterval(Self.nowTime)),
                     color: event.color)
        }
        let calendar = Calendar.current
        let reminders = reminders.compactMap { item -> WingItem? in
            guard item.hasTime, let due = item.due, calendar.isDateInToday(due),
                  !completingIDs.contains(item.id) else { return nil }
            return WingItem(kind: .reminder, title: item.title, start: due,
                            end: due.addingTimeInterval(Self.nowTime), color: item.color)
        }
        return events + reminders
    }
}
