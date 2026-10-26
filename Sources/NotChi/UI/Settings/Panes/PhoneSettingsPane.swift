// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct PhoneSettingsPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Picker("My phone", selection: $settings.phonePlatform) {
                    ForEach(PhonePlatform.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Only the services for your phone run. With None, nothing listens on the network.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if settings.phonePlatform.usesAirDrop {
                Section("iPhone · AirDrop") {
                    Text("Drop files on **iPhone** next to the stash to open AirDrop. Files your iPhone AirDrops to this Mac show up in the notch.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Keep AirDrop set to Contacts Only or Everyone in Control Center.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if settings.phonePlatform.usesQuickShare {
                Section("Android · Quick Share") {
                    Toggle(isOn: $settings.quickShareVisible) {
                        Text("Let Android phones send to this Mac")
                        Text("This Mac appears in Quick Share on phones on the same Wi-Fi. Every transfer needs your OK in the notch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    Text("To send to Android, drop files on **Android** next to the stash and scan the QR code with the phone's camera (Samsung: Quick Share → Receive → scan). Both devices must be on the same Wi-Fi.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            if settings.phonePlatform != .none {
                Section("Received files") {
                    LabeledContent("Save to") {
                        HStack(spacing: 8) {
                            Label(settings.receiveFolder.lastPathComponent, systemImage: "folder")
                                .help(settings.receiveFolder.path)
                            Button("Choose…", action: chooseFolder)
                            if !settings.receiveFolderPath.isEmpty {
                                Button("Use Downloads") { settings.receiveFolderPath = "" }
                            }
                        }
                    }
                    if settings.phonePlatform.usesAirDrop && !settings.receiveFolderPath.isEmpty {
                        Text("AirDrop always saves to Downloads; NotChi moves arrivals into this folder.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Add received files to the stash", isOn: $settings.addReceivedToStash)
                        .toggleStyle(.switch)
                    Toggle(isOn: $settings.transferNotifications) {
                        Text("Show notifications")
                        Text("Incoming shares show the sender and PIN with Accept / Decline, plus a notice when a transfer finishes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                }
            }
        }
        .settingsPaneStyle()
    }
}

extension PhoneSettingsPane {
    /// Picking the folder in an open panel also gives NotChi permission to write there.
    fileprivate func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = settings.receiveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.receiveFolderPath = url.standardizedFileURL == Settings.downloadsFolder.standardizedFileURL ? "" : url.path
    }
}
