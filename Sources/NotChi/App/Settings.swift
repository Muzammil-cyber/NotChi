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
    var portsShowAll: Bool { didSet { defaults.set(portsShowAll, forKey: "portsShowAll") } }
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
            "portsShowAll": false,
            "showMenuBarIcon": false,
            "phonePlatform": PhonePlatform.none.rawValue,
            "quickShareVisible": true,
            "addReceivedToStash": true,
            "receiveFolderPath": "",
            "transferNotifications": true,
        ])
        showWings = defaults.bool(forKey: "showWings")
        hoverToExpand = defaults.bool(forKey: "hoverToExpand")
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: "hotKey") ?? "") ?? .optionCommandN
        clipboardLimit = defaults.integer(forKey: "clipboardLimit")
        clipboardExcludedApps = defaults.stringArray(forKey: "clipboardExcludedApps") ?? []
        portsShowAll = defaults.bool(forKey: "portsShowAll")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        phonePlatform = PhonePlatform(rawValue: defaults.string(forKey: "phonePlatform") ?? "") ?? .none
        quickShareVisible = defaults.bool(forKey: "quickShareVisible")
        addReceivedToStash = defaults.bool(forKey: "addReceivedToStash")
        receiveFolderPath = defaults.string(forKey: "receiveFolderPath") ?? ""
        transferNotifications = defaults.bool(forKey: "transferNotifications")
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
