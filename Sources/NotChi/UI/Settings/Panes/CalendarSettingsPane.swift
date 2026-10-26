// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct CalendarSettingsPane: View {
    @Bindable private var settings = Settings.shared
    private let model = CalendarModel.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.calendarEnabled) {
                    Text("Show Calendar")
                    Text("Today's events in the notch's Overview tab, with a Join button for Zoom, Google Meet, Teams and Webex links.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.calendarInWings) {
                    Text("Count down to events and reminders beside the notch")
                    Text("From 5 minutes before each event or reminder with a time until a minute after it starts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .disabled(!settings.calendarEnabled)
                CalendarAccessRow()
            }
            Section("Reminders") {
                Toggle(isOn: $settings.showReminders) {
                    Text("Show reminders")
                    Text("Reminders due today and overdue appear under the agenda. Click the circle to mark one completed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .disabled(!settings.calendarEnabled)
                RemindersAccessRow()
            }
            if model.access == .granted {
                Section("Calendars") {
                    ForEach(model.calendars(), id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: shown(calendar.calendarIdentifier)) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 8, height: 8)
                                Text(calendar.title)
                                Text(calendar.source.title).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .settingsPaneStyle()
        .onAppear { model.reload() }
    }

    private func shown(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenCalendarIDs.contains(id) },
            set: { show in
                if show { settings.hiddenCalendarIDs.removeAll { $0 == id } } else { settings.hiddenCalendarIDs.append(id) }
            })
    }
}

/// Calendar access state with the button that fixes it.
struct CalendarAccessRow: View {
    private let model = CalendarModel.shared

    var body: some View {
        LabeledContent {
            switch model.access {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notDetermined:
                Button("Allow Access") { model.requestAccess() }
            case .denied:
                Button("Open System Settings") { model.openPrivacySettings() }
            }
        } label: {
            Text("Calendar access")
            Text("Read-only: NotChi shows events and finds meeting links. Nothing leaves your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Reminders access state with the button that fixes it.
struct RemindersAccessRow: View {
    private let model = CalendarModel.shared

    var body: some View {
        LabeledContent {
            switch model.reminderAccess {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notDetermined:
                Button("Allow Access") { model.requestReminderAccess() }
            case .denied:
                Button("Open System Settings") { model.openRemindersPrivacySettings() }
            }
        } label: {
            Text("Reminders access")
            Text("Shows reminders due today and lets you tick them off. Nothing leaves your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
