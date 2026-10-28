// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Carbon.HIToolbox
import Foundation
import Observation

/// User preferences, persisted to UserDefaults on every change.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    var showWings: Bool { didSet { defaults.set(showWings, forKey: "showWings") } }
    var hoverToExpand: Bool { didSet { defaults.set(hoverToExpand, forKey: "hoverToExpand") } }
    var hotKey: HotKeyPreset { didSet { defaults.set(hotKey.rawValue, forKey: "hotKey") } }
    var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") } }
    /// Bundle identifiers whose copies are never recorded.
    var clipboardExcludedApps: [String] { didSet { defaults.set(clipboardExcludedApps, forKey: "clipboardExcludedApps") } }
    /// The Dev tab (Port Sniper and future developer tools).
    var devEnabled: Bool { didSet { defaults.set(devEnabled, forKey: "devEnabled") } }
    var portsShowAll: Bool { didSet { defaults.set(portsShowAll, forKey: "portsShowAll") } }
    /// Pick the Text tool that fits the copied text when it opens.
    var textToolsAutoDetect: Bool { didSet { defaults.set(textToolsAutoDetect, forKey: "textToolsAutoDetect") } }
    /// Which phone transfer services run. Only the chosen platform's services start.
    var phonePlatform: PhonePlatform { didSet { defaults.set(phonePlatform.rawValue, forKey: "phonePlatform") } }
    /// Advertise this Mac to Android phones on the Wi-Fi (Quick Share receive).
    var quickShareVisible: Bool { didSet { defaults.set(quickShareVisible, forKey: "quickShareVisible") } }
    /// Folder for files received from phones; empty means ~/Downloads.
    var receiveFolderPath: String { didSet { defaults.set(receiveFolderPath, forKey: "receiveFolderPath") } }
    /// Notify (Notification Center) about incoming shares and finished transfers.
    var transferNotifications: Bool { didSet { defaults.set(transferNotifications, forKey: "transferNotifications") } }
    /// Put files received from a phone into the stash, ready to drag somewhere.
    var addReceivedToStash: Bool { didSet { defaults.set(addReceivedToStash, forKey: "addReceivedToStash") } }
    /// Now Playing section in Overview; when off, the media helper doesn't run at all.
    var nowPlayingEnabled: Bool { didSet { defaults.set(nowPlayingEnabled, forKey: "nowPlayingEnabled") } }
    /// Show artwork and an equalizer beside the notch while something plays.
    var nowPlayingInWings: Bool { didSet { defaults.set(nowPlayingInWings, forKey: "nowPlayingInWings") } }
    /// Calendar section in Overview.
    var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: "calendarEnabled") } }
    /// Show a countdown beside the notch from 5 minutes before an event or timed reminder
    /// until a minute after it starts.
    var calendarInWings: Bool { didSet { defaults.set(calendarInWings, forKey: "calendarInWings") } }
    /// Show reminders due today (and overdue) under the agenda, with a tick to complete them.
    var showReminders: Bool { didSet { defaults.set(showReminders, forKey: "showReminders") } }
    /// Calendar identifiers whose events are left out of the agenda.
    var hiddenCalendarIDs: [String] { didSet { defaults.set(hiddenCalendarIDs, forKey: "hiddenCalendarIDs") } }
    /// Off by default: the icon would sit right beside the notch, under the stats wing.
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    static let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    /// Where received files go (the chosen folder, or Downloads).
    var receiveFolder: URL {
        receiveFolderPath.isEmpty ? Self.downloadsFolder : URL(fileURLWithPath: receiveFolderPath, isDirectory: true)
    }

    private init() {
        defaults.register(defaults: [
            "showWings": true,
            "hoverToExpand": true,
            "hotKey": HotKeyPreset.optionCommandN.rawValue,
            "clipboardLimit": 300,
            "clipboardExcludedApps": ["com.apple.keychainaccess", "com.1password.1password", "com.bitwarden.desktop"],
            "devEnabled": true,
            "portsShowAll": false,
            "textToolsAutoDetect": true,
            "showMenuBarIcon": false,
            "phonePlatform": PhonePlatform.none.rawValue,
            "quickShareVisible": true,
            "addReceivedToStash": true,
            "receiveFolderPath": "",
            "transferNotifications": true,
            "nowPlayingEnabled": true,
            "nowPlayingInWings": true,
            "calendarEnabled": true,
            "calendarInWings": true,
            "showReminders": true,
            "hiddenCalendarIDs": [String](),
        ])
        showWings = defaults.bool(forKey: "showWings")
        hoverToExpand = defaults.bool(forKey: "hoverToExpand")
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: "hotKey") ?? "") ?? .optionCommandN
        clipboardLimit = defaults.integer(forKey: "clipboardLimit")
        clipboardExcludedApps = defaults.stringArray(forKey: "clipboardExcludedApps") ?? []
        devEnabled = defaults.bool(forKey: "devEnabled")
        portsShowAll = defaults.bool(forKey: "portsShowAll")
        textToolsAutoDetect = defaults.bool(forKey: "textToolsAutoDetect")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        phonePlatform = PhonePlatform(rawValue: defaults.string(forKey: "phonePlatform") ?? "") ?? .none
        quickShareVisible = defaults.bool(forKey: "quickShareVisible")
        addReceivedToStash = defaults.bool(forKey: "addReceivedToStash")
        receiveFolderPath = defaults.string(forKey: "receiveFolderPath") ?? ""
        transferNotifications = defaults.bool(forKey: "transferNotifications")
        nowPlayingEnabled = defaults.bool(forKey: "nowPlayingEnabled")
        nowPlayingInWings = defaults.bool(forKey: "nowPlayingInWings")
        calendarEnabled = defaults.bool(forKey: "calendarEnabled")
        calendarInWings = defaults.bool(forKey: "calendarInWings")
        showReminders = defaults.bool(forKey: "showReminders")
        hiddenCalendarIDs = defaults.stringArray(forKey: "hiddenCalendarIDs") ?? []
    }

    /// Whether anything may be drawn beside the notch while collapsed.
    var wingsWanted: Bool {
        showWings || (nowPlayingEnabled && nowPlayingInWings) || (calendarEnabled && calendarInWings)
    }
}

enum PhonePlatform: String, CaseIterable, Identifiable {
    case none, iPhone, android, both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .iPhone: "iPhone"
        case .android: "Android"
        case .both: "Both"
        }
    }

    var usesAirDrop: Bool { self == .iPhone || self == .both }
    var usesQuickShare: Bool { self == .android || self == .both }
}

/// A small fixed set of global shortcuts; avoids building a full key recorder for the MVP.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionCommandN, controlOptionSpace, commandShiftSpace, controlOptionN, disabled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionCommandN: "⌥⌘N"
        case .controlOptionSpace: "⌃⌥Space"
        case .commandShiftSpace: "⇧⌘Space"
        case .controlOptionN: "⌃⌥N"
        case .disabled: "None"
        }
    }

    /// Carbon key code and modifier mask, or nil when disabled.
    var carbon: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .optionCommandN: (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .commandShiftSpace: (UInt32(kVK_Space), UInt32(cmdKey | shiftKey))
        case .controlOptionN: (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey))
        case .disabled: nil
        }
    }
}
