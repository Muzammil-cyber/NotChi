import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, clipboard, phone, ports, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .clipboard: "Clipboard"
        case .phone: "Phone"
        case .ports: "Ports"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "doc.on.clipboard"
        case .phone: "iphone.gen3"
        case .ports: "network"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        }
    }
}

/// Shared so other code (e.g. the clipboard banner) can open Settings on a given tab.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab? = .general
    private init() {}
}

enum AppVersion {
    static let displayString: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }()
}

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared
    @State private var history: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    private var activeTab: SettingsTab { navigation.selectedTab ?? .general }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $navigation.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
                Text(AppVersion.displayString)
                    .font(.footnote)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
            .listStyle(.sidebar)
            .scrollEdgeEffectStyleSoftIfAvailable()
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(activeTab.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 620, minHeight: 440)
        .toolbar {
            // Back/forward also forces an NSToolbar, which the glass title bar needs.
            ToolbarItemGroup(placement: .navigation) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(historyIndex == 0)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(historyIndex >= history.count - 1)
            }
        }
        .onChange(of: navigation.selectedTab) { _, tab in record(tab) }
    }

    @ViewBuilder private var detail: some View {
        switch activeTab {
        case .general: GeneralSettingsPane()
        case .clipboard: ClipboardSettingsPane()
        case .phone: PhoneSettingsPane()
        case .ports: PortsSettingsPane()
        case .permissions: PermissionsSettingsPane()
        case .about: AboutSettingsPane()
        }
    }

    private func step(_ delta: Int) {
        let target = historyIndex + delta
        guard history.indices.contains(target) else { return }
        isHistoryNavigation = true
        historyIndex = target
        navigation.selectedTab = history[target]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func record(_ tab: SettingsTab?) {
        guard !isHistoryNavigation, let tab, history.last != tab else { return }
        history = Array(history.prefix(historyIndex + 1)) + [tab]
        historyIndex = history.count - 1
    }
}

extension View {
    /// Every pane uses the same grouped, transparent form so the window's glass shows through.
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }

    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
