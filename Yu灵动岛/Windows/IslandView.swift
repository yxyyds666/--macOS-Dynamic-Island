import SwiftUI

struct IslandView: View {
    @Bindable var island: IslandState
    @Bindable var appState: AppState
    @Namespace private var artworkNS

    private var mode: IslandMode { island.islandMode }
    private var notchSize: CGSize { island.notchSize }
    private var notchWidth: CGFloat { notchSize.width }
    private var notchHeight: CGFloat { notchSize.height }
    private var islandSize: CGSize { mode.size(notchSize: notchSize) }

    private var bottomCornerRadius: CGFloat {
        switch mode {
        case .idle, .playing: return AppConstants.notchCornerRadius
        case .hover, .peek, .activity: return AppConstants.islandCornerRadius
        case .expanded: return AppConstants.expandPanelCornerRadius
        }
    }

    private var islandShape: NotchShape {
        NotchShape(topCornerRadius: 0, bottomCornerRadius: bottomCornerRadius)
    }

    private var speed: Double { max(0.1, appState.animationSpeed) }

    private var sizeAnimation: Animation {
        switch mode {
        case .expanded, .peek, .hover, .activity:
            return .spring(response: 0.42 / speed, dampingFraction: 0.82, blendDuration: 0)
        case .idle, .playing:
            return .spring(response: 0.40 / speed, dampingFraction: 1.0, blendDuration: 0)
        }
    }

    private var contentAnimation: Animation { .smooth(duration: 0.22 / speed) }

    var body: some View {
        ZStack(alignment: .top) { island_body }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island_body: some View {
        ZStack(alignment: .top) {
            islandShape.fill(.black)
            content
        }
        .frame(width: islandSize.width, height: islandSize.height, alignment: .top)
        .clipShape(islandShape)
        .shadow(color: .black.opacity(mode == .idle ? 0 : 0.45), radius: 8, y: 3)
        .contentShape(islandShape)
        .onTapGesture { if mode != .expanded { island.advanceReveal() } }
        .animation(sizeAnimation, value: mode)
        .animation(sizeAnimation, value: notchWidth)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle, .hover:
            EmptyView()
        case .playing:
            PlayingCapsule(appState: appState, notchWidth: notchWidth, namespace: artworkNS)
                .transition(.opacity)
        case .activity:
            ActivityCapsule(
                appState: appState,
                activityContent: island.activityContent,
                notchWidth: notchWidth,
                notchHeight: notchHeight,
                namespace: artworkNS
            )
            .transition(.opacity)
        case .peek:
            peekContent
        case .expanded:
            expandedContent
        }
    }

    @ViewBuilder
    private var peekContent: some View {
        Group {
            switch appState.currentModule {
            case .music:
                MusicPanel(appState: appState, compact: true, namespace: artworkNS)
            case .file:
                FilePanel(appState: appState, compact: true, focused: true)
            }
        }
        .padding(.top, notchHeight + 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(appState.availableModules, id: \.self) { module in
                        ExpandedTabButton(
                            label: module.displayName,
                            icon: module.sfSymbol,
                            selected: appState.currentModule == module
                        ) {
                            withAnimation(contentAnimation) { appState.currentModule = module }
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                Button { island.collapse() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.1), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            .padding(.top, notchHeight + 6)
            .padding(.bottom, 8)

            Divider().background(.white.opacity(0.08))

            Group {
                switch appState.currentModule {
                case .music:
                    MusicPanel(appState: appState, showVolume: true, focused: true, namespace: artworkNS)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .file:
                    FilePanel(appState: appState, compact: false, focused: true)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(contentAnimation, value: appState.currentModule)
        }
        .transition(.opacity)
    }
}

private struct ExpandedTabButton: View {
    let label: String; let icon: String; let selected: Bool; let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                if selected { Text(label).font(.system(size: 12, weight: .medium))
                    .transition(.opacity.combined(with: .scale(scale: 0.85))) }
            }
            .padding(.vertical, 5).padding(.horizontal, 10)
            .background(Capsule().fill((selected || hovering)
                ? Color.white.opacity(selected ? 0.18 : 0.09) : Color.clear))
            .foregroundStyle(selected ? .white : .white.opacity(0.5))
            .animation(.smooth(duration: 0.18), value: selected)
            .animation(.easeInOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
