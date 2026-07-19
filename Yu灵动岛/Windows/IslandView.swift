import SwiftUI

/// The island's SwiftUI content. The window owns size/animation; this view fills
/// it and switches content according to the current reveal/focus state.
struct IslandView: View {
    @Bindable var appState: AppState

    private var mode: IslandMode { appState.islandMode }
    private var notchWidth: CGFloat { NSScreen.main?.notchWidth ?? AppConstants.notchWidth }
    private var notchHeight: CGFloat { NSScreen.main?.notchHeight ?? AppConstants.notchHeight }

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

    private var wrapsAroundNotch: Bool { mode == .expanded || mode == .activity || mode == .playing }

    @ViewBuilder
    private func background(_ fill: some ShapeStyle) -> some View {
        if wrapsAroundNotch {
            ExpandedNotchShape(notchCutoutWidth: notchWidth, notchCutoutHeight: notchHeight)
                .fill(fill)
        } else {
            NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
                .fill(fill)
        }
    }

    private var clip: AnyShape {
        if wrapsAroundNotch {
            return AnyShape(ExpandedNotchShape(notchCutoutWidth: notchWidth, notchCutoutHeight: notchHeight))
        }
        return AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
    }

    var body: some View {
        ZStack(alignment: .top) {
            background(.black)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(clip)
        .contentShape(clip)
        .onTapGesture {
            if mode != .expanded { appState.advanceReveal() }
        }
        .animation(.easeInOut(duration: 0.18), value: mode)
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
                MusicPanel(appState: appState)
            case .file:
                FilePanel(appState: appState, compact: true, focused: true)
            }
        }
        .padding(.top, notchHeight - 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
