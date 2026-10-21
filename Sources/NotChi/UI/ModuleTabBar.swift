import SwiftUI

struct ModuleTabBar: View {
    let modules: [NotchModule]
    let selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modules, id: \.id) { module in
                let selected = module.id == selectedID
                Button {
                    onSelect(module.id)
                } label: {
                    Label(module.title, systemImage: module.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
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
