// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

struct ClipboardSettingsPane: View {
    @Bindable private var settings = Settings.shared
    @State private var newBundleID = ""

    var body: some View {
        Form {
            Section("History") {
                LabeledContent("Keep up to") {
                    Stepper("\(settings.clipboardLimit) items", value: $settings.clipboardLimit, in: 50...2000, step: 50)
                        .monospacedDigit()
                }
                Text("Pinned items are never removed. Copies that password managers mark as concealed are never recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Ignored apps") {
                ForEach(settings.clipboardExcludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID).fontDesign(.monospaced)
                        Spacer()
                        Button(role: .destructive) {
                            settings.clipboardExcludedApps.removeAll { $0 == bundleID }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Bundle ID, e.g. com.agilebits.onepassword7", text: $newBundleID)
                        .onSubmit(addBundleID)
                    Button("Add", action: addBundleID)
                        .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Choose App…", action: chooseApp)
                }
            }
        }
        .settingsPaneStyle()
    }

    private func addBundleID() {
        let id = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !settings.clipboardExcludedApps.contains(id) else { return }
        settings.clipboardExcludedApps.append(id)
        newBundleID = ""
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        newBundleID = id
        addBundleID()
    }
}
