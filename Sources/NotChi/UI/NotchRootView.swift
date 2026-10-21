import SwiftUI

struct NotchRootView: View {
    let state: NotchState
    let settings: Settings
    let host: ModuleHost

    private var wingsVisible: Bool { state.leftWingWidth > 0 || state.rightWingWidth > 0 }

    private var shapeSize: CGSize {
        if state.isExpanded { return NotchGeometry.expandedSize }
        let notch = state.geometry.notchSize
        return CGSize(width: notch.width + state.leftWingWidth + state.rightWingWidth, height: notch.height)
    }

    /// Wings can differ in width, so the collapsed shape is shifted to keep the notch centered.
    private var shapeOffset: CGFloat {
        state.isExpanded ? 0 : (state.rightWingWidth - state.leftWingWidth) / 2
    }

    var body: some View {
        let size = shapeSize
        let expanded = state.isExpanded
        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 12 : 6, bottomRadius: expanded ? 24 : 9)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                // A shadow is an extra offscreen pass; skip it entirely while collapsed.
                .shadow(color: expanded ? .black.opacity(0.5) : .clear, radius: expanded ? 16 : 0, y: expanded ? 10 : 0)

            if expanded {
                ExpandedContent(state: state, host: host)
                    .frame(width: size.width - 24, height: size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if wingsVisible {
                CollapsedWings(host: host, state: state)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
            }
        }
        .offset(x: shapeOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: expanded)
        .animation(.easeInOut(duration: 0.2), value: state.leftWingWidth)
        .animation(.easeInOut(duration: 0.2), value: state.rightWingWidth)
        .environment(\.colorScheme, .dark)
    }
}

private struct CollapsedWings: View {
    let host: ModuleHost
    let state: NotchState

    var body: some View {
        let height = state.geometry.notchSize.height
        HStack(spacing: 0) {
            if state.leftWingWidth > 0, let left = host.leftWing {
                left.frame(width: state.leftWingWidth, height: height).clipped()
            }
            Spacer(minLength: state.geometry.notchSize.width)
            if state.rightWingWidth > 0, let right = host.rightWing {
                right.frame(width: state.rightWingWidth, height: height).clipped()
            }
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
            HStack(spacing: 0) {
                // The header shares the strip beside the hardware notch, so the tabs must fit
                // in the space left of it; fall back to icons-only tabs when they don't.
                ViewThatFits(in: .horizontal) {
                    tabBar(compact: false)
                    tabBar(compact: true)
                }
                .frame(width: sideWidth, alignment: .leading)
                Spacer(minLength: state.geometry.notchSize.width)
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
                .mask(BottomFade())
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }

    /// Width available on each side of the notch inside the header row.
    private var sideWidth: CGFloat {
        // Panel width minus the content inset (12 per side) and this view's padding (8 per side).
        let usable = NotchGeometry.expandedSize.width - 24 - 16
        return max(0, (usable - state.geometry.notchSize.width) / 2 - 8)
    }

    private func tabBar(compact: Bool) -> some View {
        ModuleTabBar(modules: host.modules, selectedID: state.selectedModuleID, compact: compact) { id in
            NotchController.shared.select(moduleID: id)
        }
        .fixedSize()
    }
}

/// Fades scrolling content out over the last few points instead of cutting rows in half
/// against the panel's rounded bottom.
private struct BottomFade: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
        }
    }
}
