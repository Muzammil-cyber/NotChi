import SwiftUI

struct NotchRootView: View {
    let state: NotchState
    let settings: Settings
    let host: ModuleHost

    private var wingsVisible: Bool { settings.showWings && host.hasWings }

    private var shapeSize: CGSize {
        if state.isExpanded { return NotchGeometry.expandedSize }
        let notch = state.geometry.notchSize
        return CGSize(width: notch.width + (wingsVisible ? NotchGeometry.wingWidth * 2 : 0), height: notch.height)
    }

    var body: some View {
        let size = shapeSize
        let expanded = state.isExpanded
        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 12 : 6, bottomRadius: expanded ? 24 : 9)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 18, y: 8)

            if expanded {
                ExpandedContent(state: state, host: host)
                    .frame(width: size.width - 24, height: size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if wingsVisible {
                CollapsedWings(host: host, notchSize: state.geometry.notchSize)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: expanded)
        .animation(.easeInOut(duration: 0.2), value: wingsVisible)
        .environment(\.colorScheme, .dark)
    }
}

private struct CollapsedWings: View {
    let host: ModuleHost
    let notchSize: CGSize

    var body: some View {
        HStack(spacing: 0) {
            (host.leftWing ?? AnyView(Color.clear))
                .frame(width: NotchGeometry.wingWidth, height: notchSize.height)
            Spacer(minLength: notchSize.width)
            (host.rightWing ?? AnyView(Color.clear))
                .frame(width: NotchGeometry.wingWidth, height: notchSize.height)
        }
        .foregroundStyle(.white)
    }
}

private struct ExpandedContent: View {
    let state: NotchState
    let host: ModuleHost

    var body: some View {
        VStack(spacing: 8) {
            // Header row shares the strip beside the hardware notch.
            HStack {
                ModuleTabBar(modules: host.modules, selectedID: state.selectedModuleID) { id in
                    NotchController.shared.select(moduleID: id)
                }
                Spacer(minLength: state.geometry.notchSize.width + 16)
                HStack(spacing: 10) {
                    Button { AppDelegate.shared?.showSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    Button { NotchController.shared.collapse() } label: {
                        Image(systemName: "chevron.up")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: max(state.geometry.notchSize.height, 26))

            if let accessory = host.topAccessory {
                accessory
            }

            host.expandedView(for: state.selectedModuleID)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }
}
