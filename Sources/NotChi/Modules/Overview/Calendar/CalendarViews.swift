// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

// MARK: - Expanded view

/// The calendar half of Overview, laid out like an "Up Next" widget: a date tile, then
/// what's happening now or next as a card, the rest of today as a quiet list, and
/// reminders due today with a circle to tick them off.
struct CalendarExpandedView: View {
    let model: CalendarModel
    private let settings = Settings.shared

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        // Re-evaluated each minute while on screen: countdowns, the date, what's "next".
        TimelineView(.everyMinute) { context in
            HStack(alignment: .top, spacing: 12) {
                DateTile(date: context.date)
                Group {
                    switch model.access {
                    case .granted: agenda(now: context.date)
                    case .notDetermined:
                        permissionPrompt(
                            text: "See today's events and reminders, and join calls in one click.",
                            button: "Allow Access", action: model.requestAccess)
                    case .denied:
                        permissionPrompt(
                            text: "Turn on NotChi in Privacy & Security → Calendars.",
                            button: "Open System Settings", action: model.openPrivacySettings)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.leading, 14)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .enableInjection()
    }

    private func agenda(now: Date) -> some View {
        let timed = model.timedEvents.filter { $0.end > now }
        let hero = timed.first
        let later = Array(timed.dropFirst())
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !model.allDayEvents.isEmpty { allDayRow }
                if let hero {
                    HeroCard(event: hero, now: now)
                } else {
                    nothingLeft
                }
                if !later.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(later) { CompactEventRow(event: $0) }
                    }
                }
                if settings.showReminders { remindersSection(now: now) }
            }
            .padding(.trailing, 14)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private var allDayRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.allDayEvents) { event in
                    HStack(spacing: 5) {
                        Circle().fill(event.color).frame(width: 6, height: 6)
                        Text(event.title).lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(event.color.opacity(0.18)))
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var nothingLeft: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.events.isEmpty ? "No events today" : "Nothing else today")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            if let next = model.tomorrowFirst {
                HStack(spacing: 5) {
                    Circle().fill(next.color).frame(width: 6, height: 6)
                    Text("Tomorrow \(next.start.formatted(date: .omitted, time: .shortened)) · \(next.title)")
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func remindersSection(now: Date) -> some View {
        switch model.reminderAccess {
        case .granted:
            if !model.reminders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(title: "Reminders", count: model.reminders.count - model.completingIDs.count)
                    ForEach(model.reminders) { item in
                        ReminderRow(item: item, now: now, done: model.completingIDs.contains(item.id)) {
                            model.complete(item)
                        }
                    }
                }
                .padding(.top, 2)
            }
        case .notDetermined:
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .foregroundStyle(.white.opacity(0.5))
                Text("Show today's reminders here")
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 4)
                Button("Allow") { model.requestReminderAccess() }
                    .buttonStyle(TintedPillButtonStyle(tint: .white.opacity(0.14)))
            }
            .font(.system(size: 11))
        case .denied:
            EmptyView()
        }
    }

    private func permissionPrompt(text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(TintedPillButtonStyle(tint: .accentColor))
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
    }
}

/// Today's date as a tile, after the macOS Calendar widget: the weekday in red, the day
/// number large, the month underneath, all centered.
struct DateTile: View {
    let date: Date

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    /// Width every line is sized to; the font size is derived from it, so the three lines
    /// are the same width and differ in size.
    private static let lineWidth: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {
            line(date.formatted(.dateTime.weekday(.abbreviated)).uppercased(), weight: .bold)
                .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                .padding(.bottom,-15)
            line(date.formatted(.dateTime.day(.twoDigits)), weight: .semibold, digits: true)
                .foregroundStyle(.white.opacity(0.92))
            line(date.formatted(.dateTime.month(.wide)).uppercased(), weight: .semibold)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top,-6)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .frame(width: Self.lineWidth + 30)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .enableInjection()
    }

    /// One line of the tile, at the font size that makes `text` exactly `lineWidth` wide.
    private func line(_ text: String, weight: Font.Weight, digits: Bool = false) -> some View {
        let probe: CGFloat = 100
        let nsWeight: NSFont.Weight = weight == .bold ? .bold : .semibold
        let font = digits
            ? NSFont.monospacedDigitSystemFont(ofSize: probe, weight: nsWeight)
            : NSFont.systemFont(ofSize: probe, weight: nsWeight)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        let size = measured > 0 ? probe * Self.lineWidth / measured : probe
        return Text(text)
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .frame(width: Self.lineWidth)
    }
}




/// The event happening now, or the next one: status, title, place and the Join button.
struct HeroCard: View {
    let event: AgendaEvent
    let now: Date

    private var isNow: Bool { event.start <= now }
    private var minutesAway: Int { Int((event.start.timeIntervalSince(now) / 60).rounded(.up)) }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(status)
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(isNow || minutesAway <= 5 ? Color.green : event.color)
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if let meeting = event.meeting {
                    Button { meeting.open() } label: {
                        Label("Join \(meeting.service.rawValue)", systemImage: "video.fill")
                    }
                    .buttonStyle(TintedPillButtonStyle(tint: isNow || minutesAway <= 5 ? .green : .white.opacity(0.14)))
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(event.color.opacity(0.12)))
        .enableInjection()
    }

    private var status: String {
        if isNow {
            return "NOW · ENDS \(event.end.formatted(date: .omitted, time: .shortened))".uppercased()
        }
        if minutesAway < 60 { return "IN \(minutesAway) MIN" }
        let hours = minutesAway / 60, minutes = minutesAway % 60
        return minutes == 0 ? "IN \(hours) HR" : "IN \(hours) HR \(minutes) MIN"
    }

    private var detail: String {
        let time = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        if let location = event.location, event.meeting == nil { return "\(time) · \(location)" }
        return time
    }
}

/// Later events: time, color dot, title, and a small video icon when there's a link.
struct CompactEventRow: View {
    let event: AgendaEvent

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        HStack(spacing: 8) {
            Text(event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 58, alignment: .leading)
            Circle().fill(event.color).frame(width: 6, height: 6)
            Text(event.title)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let meeting = event.meeting {
                Button { meeting.open() } label: {
                    Image(systemName: "video.fill").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .help("Join on \(meeting.service.rawValue)")
            }
        }
        .enableInjection()
    }
}

struct SectionLabel: View {
    let title: String
    let count: Int

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .kerning(0.5)
            if count > 0 { Text("\(count)").foregroundStyle(.white.opacity(0.35)) }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white.opacity(0.45))
        .enableInjection()
    }
}

/// One reminder with the Reminders-style circle: a single click ticks it off.
struct ReminderRow: View {
    let item: ReminderItem
    let now: Date
    let done: Bool
    let complete: () -> Void

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: complete) {
                ZStack {
                    Circle().strokeBorder(item.color, lineWidth: 1.5)
                    if done {
                        Circle().fill(item.color)
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            .help("Mark as completed")
            .accessibilityLabel(done ? "Completed" : "Mark \(item.title) as completed")
            .animation(.spring(duration: 0.25), value: done)

            Text(item.title)
                .font(.system(size: 12))
                .strikethrough(done, color: .white.opacity(0.4))
                .foregroundStyle(.white.opacity(done ? 0.4 : 0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let label = dueLabel {
                Text(label)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(item.isOverdue(now: now) && !done ? Color.red.opacity(0.9) : .white.opacity(0.45))
            }
        }
        .transition(.opacity)
        .enableInjection()
    }

    private var dueLabel: String? {
        guard let due = item.due else { return nil }
        if !Calendar.current.isDateInToday(due) {
            return Calendar.current.isDateInYesterday(due) ? "Yesterday" : due.formatted(.dateTime.month(.abbreviated).day())
        }
        return item.hasTime ? due.formatted(date: .omitted, time: .shortened) : nil
    }
}

/// Like the transfer card's `PillButtonStyle`, with a custom tint (green to join a live call).
struct TintedPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

#Preview("Date tile") {
    DateTile(date: .now)
        .padding(20)
        .background(.black)
}
