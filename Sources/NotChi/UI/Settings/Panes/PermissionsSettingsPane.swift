// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct PermissionsSettingsPane: View {
    private let accessibility = AccessibilityStatus.shared

    var body: some View {
        Form {
            Section("Accessibility") {
                LabeledContent {
                    if accessibility.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                } label: {
                    Text("Auto-paste")
                    Text(accessibility.isTrusted
                         ? "Picking a clipboard item pastes it straight into the app you're using."
                         : "Without it, picking an item only copies it and you press ⌘V yourself.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !accessibility.isTrusted {
                    Text("Already enabled in the list? After an update macOS may treat NotChi as a new app: select it, remove it with −, then add it again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Calendar") {
                CalendarAccessRow()
                RemindersAccessRow()
            }
            Section("Not required") {
                Text("Hover detection, the global shortcut, clipboard history, system stats, Now Playing and port scanning need no permissions.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .settingsPaneStyle()
        .onAppear { accessibility.refresh() }
    }
}
