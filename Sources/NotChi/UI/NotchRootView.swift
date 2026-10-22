import SwiftUI

struct NotchRootView: View {
    let state: NotchState
    let settings: Settings
    let host: ModuleHost

    private var transferActive: Bool { host.transfer?.isActive ?? false }

    /// A running transfer always gets some room beside the notch, even where the stats
    /// wings have stepped aside for menus; it's brief and the user is waiting on it.
    private var leftWidth: CGFloat { transferActive ? max(state.leftWingWidth, 56) : state.leftWingWidth }
    private var rightWidth: CGFloat { transferActive ? max(state.rightWingWidth, 56) : state.rightWingWidth }

    private var wingsVisible: Bool { leftWidth > 0 || rightWidth > 0 }

    private var collapsedSize: CGSize {
        let notch = state.geometry.notchSize
        return CGSize(width: notch.width + leftWidth + rightWidth,
                      height: state.geometry.collapsedHeight(withWings: wingsVisible))
    }

    private var shapeSize: CGSize {
        state.isExpanded ? NotchGeometry.expandedSize : collapsedSize
    }

    /// Wings can differ in width, so the collapsed shape is shifted to keep the notch centered.
    private var shapeOffset: CGFloat {
        state.isExpanded ? 0 : (rightWidth - leftWidth) / 2
    }

    var body: some View {
        let size = shapeSize
        let expanded = state.isExpanded
        ZStack(alignment: .top) {
            // Fixed full-panel canvas; only the path inside animates (see NotchShape).
            NotchShape(size: size, offsetX: shapeOffset,
                       topRadius: expanded ? 12 : 6, bottomRadius: expanded ? 24 : 9)
                .fill(Color.black)
                // A shadow is an extra offscreen pass; skip it entirely while collapsed.
                .shadow(color: expanded ? .black.opacity(0.5) : .clear, radius: expanded ? 16 : 0, y: expanded ? 10 : 0)

            if expanded {
                // Fixed size and an opacity-only transition: scaling would re-rasterize all
                // text every frame. The fade-in waits until the shape has mostly grown.
                ExpandedContent(state: state, host: host)
                    .frame(width: NotchGeometry.expandedSize.width - 24, height: NotchGeometry.expandedSize.height)
                    // Clip to the same animated silhouette so content (including AppKit-backed
                    // scroll views, which ignore the fade) shrinks together with the background.
                    .clipShape(NotchShape(size: size, offsetX: shapeOffset,
                                          topRadius: expanded ? 12 : 6, bottomRadius: expanded ? 24 : 9))
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.12)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
            }

            if !expanded && wingsVisible {
                // Always laid out at the final collapsed size; only opacity animates.
                CollapsedWings(host: host, state: state, left: leftWidth, right: rightWidth,
                               transferActive: transferActive)
                    .frame(width: collapsedSize.width, height: collapsedSize.height)
                    .offset(x: shapeOffset)
                    .transition(.opacity)
            }
        }
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
    let left: CGFloat
    let right: CGFloat
    let transferActive: Bool

    var body: some View {
        let height = state.geometry.collapsedHeight(withWings: true)
        HStack(spacing: 0) {
            if left > 0 { wing(.left).frame(width: left, height: height).clipped() }
            Spacer(minLength: state.geometry.notchSize.width)
            if right > 0 { wing(.right).frame(width: right, height: height).clipped() }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private func wing(_ side: TransferWing.Side) -> some View {
        if transferActive, let transfer = host.transfer {
            TransferWing(coordinator: transfer, side: side)
        } else {
            (side == .left ? host.leftWing : host.rightWing) ?? AnyView(Color.clear)
        }
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

            if let transfer = host.transfer, transfer.isActive {
                TransferCard(coordinator: transfer)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
