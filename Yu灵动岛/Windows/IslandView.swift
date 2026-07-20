import SwiftUI

/// The island's SwiftUI content. The window owns size/animation; this view fills
/// it and switches content according to the current reveal/focus state.
struct IslandView: View {
    @Bindable var appState: AppState

    private var mode: IslandMode { appState.islandMode }
    private var notchWidth: CGFloat { appState.notchSize.width }
    private var notchHeight: CGFloat { appState.notchSize.height }

    private var topCornerRadius: CGFloat {
        mode == .idle ? AppConstants.notchCornerRadius : AppConstants.islandTopCornerRadius
    }

    private var bottomCornerRadius: CGFloat {
        switch mode {
        case .idle, .playing: return AppConstants.notchCornerRadius
        case .hover, .peek, .activity: return AppConstants.islandCornerRadius
        case .expanded: return AppConstants.expandPanelCornerRadius
        }
    }

    // Every state renders one solid shape that covers the physical notch — no
    // cutout, no gap. The top edge stays flush with the screen with a small
    // concave shoulder; the panel simply drapes further down as it grows.
    private var islandShape: NotchShape {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }

    @ViewBuilder
    private func background(_ fill: some ShapeStyle) -> some View {
        islandShape.fill(fill)
    }

    private var clip: AnyShape {
        AnyShape(islandShape)
    }

    var body: some View {
        ZStack(alignment: .top) {
            background(.black)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(clip)
        .contentShape(Rectangle())
        .onTapGesture {
            if mode != .expanded { appState.advanceReveal() }
        }
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.78, blendDuration: 0.08), value: mode)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle, .hover:
            EmptyView()
        case .playing:
            CollapsedPlaybackActivity(appState: appState, notchWidth: notchWidth)
                .transition(.opacity)
        case .activity:
            ActivityCapsule(appState: appState, notchWidth: notchWidth, notchHeight: notchHeight)
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
                MusicPanel(appState: appState, compact: true)
            case .file:
                FilePanel(appState: appState, compact: true, focused: true)
            }
        }
        .padding(.top, notchHeight + 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var expandedContent: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                Group {
                    if appState.showMusicModule {
                        MusicPanel(
                            appState: appState,
                            showVolume: true,
                            focused: appState.currentModule == .music
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: notchWidth)

                Group {
                    if appState.showFileModule {
                        FilePanel(
                            appState: appState,
                            compact: false,
                            focused: appState.currentModule == .file
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, notchHeight + 8)
            .padding(.bottom, 20)

            Button {
                appState.collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, notchHeight + 10)
            .padding(.trailing, 12)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
