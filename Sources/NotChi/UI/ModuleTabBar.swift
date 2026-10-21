import SwiftUI

struct ModuleTabBar: View {
    let modules: [NotchModule]
    let selectedID: String
    /// Icons only, with the title shown just for the selected tab.
    var compact = false
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modules, id: \.id) { module in
                let selected = module.id == selectedID
                Button {
                    onSelect(module.id)
                } label: {
                    Group {
                        if compact && !selected {
                            Image(systemName: module.systemImage)
                        } else {
                            Label(module.title, systemImage: module.systemImage).labelStyle(.titleAndIcon)
                        }
                    }
                        .font(.system(size: 11, weight: .medium))
                        .help(module.title)
                        .padding(.horizontal, compact ? 7 : 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.16) : .clear))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
