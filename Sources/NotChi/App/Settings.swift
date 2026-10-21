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
    /// Off by default: the icon would sit right beside the notch, under the stats wing.
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    private init() {
        defaults.register(defaults: [
            "showWings": true,
            "hoverToExpand": true,
            "hotKey": HotKeyPreset.optionCommandN.rawValue,
            "clipboardLimit": 300,
            "clipboardExcludedApps": ["com.apple.keychainaccess", "com.1password.1password", "com.bitwarden.desktop"],
            "portsShowAll": false,
            "showMenuBarIcon": false,
        ])
        showWings = defaults.bool(forKey: "showWings")
        hoverToExpand = defaults.bool(forKey: "hoverToExpand")
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: "hotKey") ?? "") ?? .optionCommandN
        clipboardLimit = defaults.integer(forKey: "clipboardLimit")
        clipboardExcludedApps = defaults.stringArray(forKey: "clipboardExcludedApps") ?? []
        portsShowAll = defaults.bool(forKey: "portsShowAll")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
    }
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
