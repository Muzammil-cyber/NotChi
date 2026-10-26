// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    @Bindable private var settings = Settings.shared
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                                     set: setLaunchAtLogin)) {
                    Text("Launch at login")
                    if loginStatus == .requiresApproval {
                        Text("Approve NotChi in System Settings → General → Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("Usually not needed: hover the notch or use the shortcut. The icon sits next to the notch, so the stats wing makes room for it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }

            Section("Notch") {
                Picker("Toggle shortcut", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle(isOn: $settings.hoverToExpand) {
                    Text("Expand on hover")
                    Text("When off, open the notch with the shortcut or by dragging a file onto it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.showWings) {
                    Text("Show system stats beside the notch")
                    Text("Each side hides itself automatically when menus or menu bar icons need the space.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit NotChi", role: .destructive) { NSApp.terminate(nil) }
                }
            }
        }
        .settingsPaneStyle()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("NotChi: launch at login change failed: %@", error.localizedDescription)
        }
        loginStatus = SMAppService.mainApp.status
    }
}
