import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = Permissions.isAccessibilityTrusted
    @State private var excludedText = ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker("Toggle shortcut", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Expand on hover", isOn: $settings.hoverToExpand)
                Toggle("Show system stats beside the notch", isOn: $settings.showWings)
            }

            Section("Clipboard") {
                Stepper("Keep \(settings.clipboardLimit) items", value: $settings.clipboardLimit, in: 50...2000, step: 50)
                LabeledContent("Ignored apps") {
                    TextField("Bundle IDs, comma separated", text: $excludedText)
                        .onSubmit(saveExcluded)
                }
                HStack {
                    Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(axTrusted ? .green : .orange)
                    Text(axTrusted ? "Accessibility granted: auto-paste is on"
                                   : "Grant Accessibility to paste into the frontmost app")
                    Spacer()
                    if !axTrusted {
                        Button("Open Settings") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Ports") {
                Toggle("Show all listening ports (not just dev servers)", isOn: $settings.portsShowAll)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { excludedText = settings.clipboardExcludedApps.joined(separator: ", ") }
        .onDisappear(perform: saveExcluded)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = Permissions.isAccessibilityTrusted
        }
    }

    private func saveExcluded() {
        settings.clipboardExcludedApps = excludedText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
