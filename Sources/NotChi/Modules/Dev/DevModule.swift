// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// The "Dev" tab: home for developer utilities (Port Sniper today). Optional, since not
/// everyone writes code; turned off in Settings → Dev it's hidden and nothing runs.
/// New developer tools go in `tools` rather than becoming top-level tabs.
@MainActor
final class DevModule: NotchModule {
    let id = "dev"
    let title = "Dev"
    let systemImage = "hammer"

    let tools: [NotchModule]
    private let settings = Settings.shared
    private var visible = false
    private var views: [String: AnyView] = [:]
    /// The tool on screen when there are several.
    fileprivate var selectedToolID: String

    init(tools: [NotchModule]) {
        self.tools = tools
        selectedToolID = tools.first?.id ?? ""
    }

    var isEnabled: Bool { settings.devEnabled }

    var selectedTool: NotchModule? { tools.first { $0.id == selectedToolID } ?? tools.first }

    func contains(toolID: String) -> Bool { tools.contains { $0.id == toolID } }

    func select(toolID: String) {
        guard contains(toolID: toolID) else { return }
        selectedToolID = toolID
        syncVisibility()
    }

    func view(for tool: NotchModule) -> AnyView {
        if let view = views[tool.id] { return view }
        let view = tool.makeExpandedView()
        views[tool.id] = view
        return view
    }

    func makeExpandedView() -> AnyView { AnyView(DevView(module: self)) }

    func start() { tools.forEach { $0.start() } }
    func stop() { tools.forEach { $0.stop() } }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        syncVisibility()
    }

    /// Only the shown tool does on-screen work (e.g. port scanning).
    private func syncVisibility() {
        let selected = selectedTool?.id
        for tool in tools { tool.setVisible(visible && tool.id == selected) }
    }
}

private struct DevView: View {
    let module: DevModule
    @State private var selection: String

    init(module: DevModule) {
        self.module = module
        _selection = State(initialValue: module.selectedToolID)
    }

    var body: some View {
        VStack(spacing: 6) {
            // With a single tool there's nothing to pick; show it as is.
            if module.tools.count > 1 {
                Picker("Tool", selection: $selection) {
                    ForEach(module.tools, id: \.id) { tool in
                        Label(tool.title, systemImage: tool.systemImage).tag(tool.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: selection) { _, id in module.select(toolID: id) }
            }
            if let tool = module.tools.first(where: { $0.id == selection }) {
                module.view(for: tool)
                    .id(tool.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
