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

struct NowPlayingSettingsPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.nowPlayingEnabled) {
                    Text("Show Now Playing")
                    Text("The current track from Music, Spotify, browsers and other players, with playback controls, in the notch's Overview tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                Toggle(isOn: $settings.nowPlayingInWings) {
                    Text("Show artwork beside the notch while playing")
                    Text("Replaces the system stats until playback pauses.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .disabled(!settings.nowPlayingEnabled)
            }
            Section("How it works") {
                Text("Since macOS 15.4 apps can't read what's playing directly, so NotChi runs a small helper (mediaremote-adapter) through the system's Perl. It only reports changes, and it doesn't run while this is off.")
                    .font(.callout).foregroundStyle(.secondary)
                if !MediaRemoteBridge.isAvailable {
                    Label("The helper is missing from this build.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .settingsPaneStyle()
    }
}

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

struct DevSettingsPane: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.devEnabled) {
                    Text("Show Dev tab")
                    Text("Developer utilities: Port Sniper (more coming). Off hides the tab; nothing runs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }
            Section("Port Sniper") {
                Toggle(isOn: $settings.portsShowAll) {
                    Text("Show all listening ports")
                    Text("By default only dev servers and Docker/OrbStack containers are listed; system services and desktop apps are hidden.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }
            Section("Docker") {
                Text("Container ports are detected through the Docker engine socket (OrbStack, Docker Desktop, Colima, Rancher Desktop). Stopping a container row runs `docker stop`; the engine itself is never killed.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .settingsPaneStyle()
    }
}

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

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: AppLogo.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("NotChi logo")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotChi").font(.title2.weight(.semibold))
                        Text(AppVersion.displayString).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("License", value: "PolyForm Noncommercial 1.0.0")
                LabeledContent("Copyright", value: "© 2026 Muhammad Muzammil Loya")
                LabeledContent("Source") {
                    Link("github.com/Muzammil-cyber/NotChi", destination: URL(string: "https://github.com/Muzammil-cyber/NotChi")!)
                }
                LabeledContent("Commercial licensing") {
                    Link("muzammilloya.dev", destination: URL(string: "https://muzammilloya.dev")!)
                }
                LabeledContent("Third-party components") {
                    Text("NearDrop · Google Nearby · SwiftProtobuf · mediaremote-adapter").foregroundStyle(.secondary)
                }
                LabeledContent("Data") {
                    Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.support) }
                }
            }
        }
        .settingsPaneStyle()
    }
}
